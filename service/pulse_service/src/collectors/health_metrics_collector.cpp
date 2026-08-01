#include "collectors/health_metrics_collector.hpp"

#include "collectors/gpu_adapter_info.hpp"
#include "collectors/process_metrics.hpp"
#include "collectors/system_overview_info.hpp"
#include "logging/logger.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <map>
#include <optional>
#include <set>
#include <unordered_set>
#include <vector>

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <Pdh.h>
#include <PdhMsg.h>
#include <TlHelp32.h>
#include <Psapi.h>
#include <VersionHelpers.h>

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <tcpmib.h>
#include <tcpestats.h>
#include <netioapi.h>
#include <dxgi.h>

#pragma comment(lib, "pdh.lib")
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "psapi.lib")
#pragma comment(lib, "version.lib")

namespace pulse {
namespace {

constexpr size_t kTopProcessLimit = 8;

uint64_t FileTimeToU64(const FILETIME& ft) {
  ULARGE_INTEGER u{};
  u.LowPart = ft.dwLowDateTime;
  u.HighPart = ft.dwHighDateTime;
  return u.QuadPart;
}

int64_t NowUnixMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(system_clock::now().time_since_epoch())
      .count();
}

std::string NarrowFromWide(const wchar_t* wide) {
  if (wide == nullptr || wide[0] == L'\0') return {};
  const int needed =
      WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (needed <= 1) return {};
  std::string out(static_cast<size_t>(needed - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), needed, nullptr,
                      nullptr);
  return out;
}

std::string TrimCopy(std::string s) {
  while (!s.empty() && (s.back() == ' ' || s.back() == '\t')) s.pop_back();
  size_t i = 0;
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t')) ++i;
  return s.substr(i);
}

std::string AsciiLowerCopy(std::string s) {
  for (char& c : s) {
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
  }
  return s;
}

std::string BaseFileNameAscii(const std::string& path_or_name) {
  const auto slash = path_or_name.find_last_of("\\/");
  if (slash == std::string::npos) return path_or_name;
  return path_or_name.substr(slash + 1);
}

/// Well-known system binaries whose on-disk path is stable under %SystemRoot%.
/// Used when OpenProcess is denied (PPL / LocalService) so the UI can still
/// extract the shell icon from the file.
std::string KnownSystemExecutablePath(const std::string& name) {
  const std::string file = AsciiLowerCopy(BaseFileNameAscii(name));
  if (file.empty()) return {};

  wchar_t windows_dir[MAX_PATH]{};
  wchar_t system_dir[MAX_PATH]{};
  if (GetWindowsDirectoryW(windows_dir, MAX_PATH) == 0) return {};
  if (GetSystemDirectoryW(system_dir, MAX_PATH) == 0) return {};

  const std::string win = NarrowFromWide(windows_dir);
  const std::string sys = NarrowFromWide(system_dir);
  if (win.empty() || sys.empty()) return {};

  if (file == "explorer.exe") {
    return win + "\\explorer.exe";
  }

  static constexpr const char* kSystem32[] = {
      "svchost.exe",   "dwm.exe",         "csrss.exe",    "wininit.exe",
      "services.exe",  "lsass.exe",       "winlogon.exe", "smss.exe",
      "fontdrvhost.exe", "sihost.exe",    "taskhostw.exe",
      "runtimebroker.exe",
  };
  for (const char* known : kSystem32) {
    if (file == known) {
      return sys + "\\" + known;
    }
  }
  return {};
}

/// Resolve executable path for IPC (wire field `path`).
/// Prefer QueryFullProcessImageName when LocalService can open the process;
/// otherwise fall back to a known SystemRoot path for common system binaries.
std::string ResolveProcessExecutablePath(uint32_t pid, const std::string& name) {
  if (pid > 0) {
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (h != nullptr) {
      wchar_t path[MAX_PATH * 4];
      DWORD size = static_cast<DWORD>(sizeof(path) / sizeof(path[0]));
      std::string resolved;
      if (QueryFullProcessImageNameW(h, 0, path, &size) && path[0] != L'\0') {
        resolved = NarrowFromWide(path);
      }
      CloseHandle(h);
      if (!resolved.empty()) return resolved;
    }
  }
  return KnownSystemExecutablePath(name);
}

void FillExecutablePaths(std::vector<ipc::HealthProcessEntry>* entries) {
  if (entries == nullptr) return;
  for (auto& e : *entries) {
    if (!e.path.empty()) continue;
    e.path = ResolveProcessExecutablePath(e.pid, e.name);
  }
}

template <typename ScoreFn>
void KeepTopN(std::vector<ipc::HealthProcessEntry>* entries, size_t n,
              ScoreFn score) {
  if (entries->size() <= n) {
    std::sort(entries->begin(), entries->end(),
              [&](const auto& a, const auto& b) { return score(a) > score(b); });
    return;
  }
  std::partial_sort(
      entries->begin(), entries->begin() + static_cast<std::ptrdiff_t>(n),
      entries->end(),
      [&](const auto& a, const auto& b) { return score(a) > score(b); });
  entries->resize(n);
}

uint32_t ParsePidFromGpuInstance(const wchar_t* name) {
  // Typical: "pid_1234_luid_..._eng_0_engtype_3D"
  if (name == nullptr) return 0;
  const wchar_t* p = wcsstr(name, L"pid_");
  if (p == nullptr) return 0;
  p += 4;
  uint32_t pid = 0;
  while (*p >= L'0' && *p <= L'9') {
    pid = pid * 10 + static_cast<uint32_t>(*p - L'0');
    ++p;
  }
  return pid;
}

// --- NtQuerySystemInformation(SystemProcessInformation) ---
// Same process snapshot family Task Manager uses. No OpenProcess / no PDH
// Process(*) counters. Layout matches Vista+ / Win7+ (Process Hacker / PHNT).

constexpr ULONG kSystemProcessInformation = 5;
constexpr LONG kStatusSuccess = 0;
constexpr LONG kStatusInfoLengthMismatch = static_cast<LONG>(0xC0000004L);

using NtQuerySystemInformationFn = LONG(WINAPI*)(ULONG, PVOID, ULONG, PULONG);

#pragma pack(push, 8)
struct PulseUnicodeString {
  USHORT Length = 0;
  USHORT MaximumLength = 0;
  PWSTR Buffer = nullptr;
};

struct PulseSystemProcessInformation {
  ULONG NextEntryOffset = 0;
  ULONG NumberOfThreads = 0;
  LARGE_INTEGER WorkingSetPrivateSize{};
  ULONG HardFaultCount = 0;
  ULONG NumberOfThreadsHighWatermark = 0;
  ULONGLONG CycleTime = 0;
  LARGE_INTEGER CreateTime{};
  LARGE_INTEGER UserTime{};
  LARGE_INTEGER KernelTime{};
  PulseUnicodeString ImageName{};
  LONG BasePriority = 0;
  HANDLE UniqueProcessId = nullptr;
  HANDLE InheritedFromUniqueProcessId = nullptr;
  ULONG HandleCount = 0;
  ULONG SessionId = 0;
  ULONG_PTR UniqueProcessKey = 0;
  SIZE_T PeakVirtualSize = 0;
  SIZE_T VirtualSize = 0;
  ULONG PageFaultCount = 0;
  SIZE_T PeakWorkingSetSize = 0;
  SIZE_T WorkingSetSize = 0;
  SIZE_T QuotaPeakPagedPoolUsage = 0;
  SIZE_T QuotaPagedPoolUsage = 0;
  SIZE_T QuotaPeakNonPagedPoolUsage = 0;
  SIZE_T QuotaNonPagedPoolUsage = 0;
  SIZE_T PagefileUsage = 0;
  SIZE_T PeakPagefileUsage = 0;
  SIZE_T PrivatePageCount = 0;
  LARGE_INTEGER ReadOperationCount{};
  LARGE_INTEGER WriteOperationCount{};
  LARGE_INTEGER OtherOperationCount{};
  LARGE_INTEGER ReadTransferCount{};
  LARGE_INTEGER WriteTransferCount{};
  LARGE_INTEGER OtherTransferCount{};
};
#pragma pack(pop)

// Verified against Vista+/Win7+ SYSTEM_PROCESS_INFORMATION (x64).
static_assert(offsetof(PulseSystemProcessInformation, UserTime) == 40,
              "SYSTEM_PROCESS_INFORMATION UserTime offset");
static_assert(offsetof(PulseSystemProcessInformation, KernelTime) == 48,
              "SYSTEM_PROCESS_INFORMATION KernelTime offset");
static_assert(offsetof(PulseSystemProcessInformation, ImageName) == 56,
              "SYSTEM_PROCESS_INFORMATION ImageName offset");
static_assert(offsetof(PulseSystemProcessInformation, UniqueProcessId) == 80,
              "SYSTEM_PROCESS_INFORMATION UniqueProcessId offset");
static_assert(offsetof(PulseSystemProcessInformation, HandleCount) == 96,
              "SYSTEM_PROCESS_INFORMATION HandleCount offset");
static_assert(offsetof(PulseSystemProcessInformation, WorkingSetSize) == 144,
              "SYSTEM_PROCESS_INFORMATION WorkingSetSize offset");

NtQuerySystemInformationFn ResolveNtQuerySystemInformation() {
  static NtQuerySystemInformationFn fn = []() -> NtQuerySystemInformationFn {
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (ntdll == nullptr) return nullptr;
    return reinterpret_cast<NtQuerySystemInformationFn>(
        GetProcAddress(ntdll, "NtQuerySystemInformation"));
  }();
  return fn;
}

std::string ProcessNameFromSpi(const PulseSystemProcessInformation& info) {
  const uint32_t pid =
      static_cast<uint32_t>(reinterpret_cast<uintptr_t>(info.UniqueProcessId));
  if (info.ImageName.Buffer != nullptr && info.ImageName.Length > 0) {
    const size_t chars = info.ImageName.Length / sizeof(wchar_t);
    std::wstring w(info.ImageName.Buffer, chars);
    return NarrowFromWide(w.c_str());
  }
  if (pid == 0) return "System Idle Process";
  if (pid == 4) return "System";
  return "pid_" + std::to_string(pid);
}

}  // namespace

HealthMetricsCollector::HealthMetricsCollector() = default;

HealthMetricsCollector::~HealthMetricsCollector() { Shutdown(); }

void HealthMetricsCollector::SetProcessCpuMode(ProcessCpuMode mode) {
  std::lock_guard lock(mu_);
  process_cpu_.set_mode(mode);
  // Force baseline rebuild so mode switch does not mix formulas.
  have_proc_baseline_ = false;
  prev_proc_cpu_.clear();
  force_full_resync_ = true;
  Logger::Instance().Info(
      "HealthMetrics",
      "Process CPU mode set to " + ProcessCpuModeName(mode));
}

ProcessCpuMode HealthMetricsCollector::process_cpu_mode() const {
  return process_cpu_.mode();
}

bool HealthMetricsCollector::Initialize() {
  std::lock_guard lock(mu_);
  if (initialized_) return true;

  PDH_HQUERY query = nullptr;
  if (PdhOpenQueryW(nullptr, 0, &query) == ERROR_SUCCESS) {
    pdh_query_ = query;
    PDH_HCOUNTER read_counter = nullptr;
    PDH_HCOUNTER write_counter = nullptr;
    if (PdhAddEnglishCounterW(query, L"\\PhysicalDisk(_Total)\\Disk Read Bytes/sec",
                              0, &read_counter) == ERROR_SUCCESS &&
        PdhAddEnglishCounterW(query,
                              L"\\PhysicalDisk(_Total)\\Disk Write Bytes/sec", 0,
                              &write_counter) == ERROR_SUCCESS) {
      pdh_disk_read_ = read_counter;
      pdh_disk_write_ = write_counter;
      pdh_disk_ok_ = true;
    }

    PDH_HCOUNTER read_all = nullptr;
    PDH_HCOUNTER write_all = nullptr;
    if (PdhAddEnglishCounterW(query, L"\\PhysicalDisk(*)\\Disk Read Bytes/sec",
                              0, &read_all) == ERROR_SUCCESS &&
        PdhAddEnglishCounterW(query, L"\\PhysicalDisk(*)\\Disk Write Bytes/sec",
                              0, &write_all) == ERROR_SUCCESS) {
      pdh_disk_read_all_ = read_all;
      pdh_disk_write_all_ = write_all;
      pdh_disk_instances_ok_ = true;
    }

    // Task Manager GPU graph: max utilization across all GPU engines.
    PDH_HCOUNTER gpu_counter = nullptr;
    if (PdhAddEnglishCounterW(query, L"\\GPU Engine(*)\\Utilization Percentage",
                              0, &gpu_counter) == ERROR_SUCCESS) {
      pdh_gpu_ = gpu_counter;
      pdh_gpu_ok_ = true;
    } else if (PdhAddEnglishCounterW(
                   query, L"\\GPU Engine(*engtype_3D)\\Utilization Percentage",
                   0, &gpu_counter) == ERROR_SUCCESS) {
      pdh_gpu_ = gpu_counter;
      pdh_gpu_ok_ = true;
    }

    PDH_HCOUNTER gpu_ded = nullptr;
    PDH_HCOUNTER gpu_shr = nullptr;
    if (PdhAddEnglishCounterW(query, L"\\GPU Adapter Memory(*)\\Dedicated Usage",
                              0, &gpu_ded) == ERROR_SUCCESS &&
        PdhAddEnglishCounterW(query, L"\\GPU Adapter Memory(*)\\Shared Usage", 0,
                              &gpu_shr) == ERROR_SUCCESS) {
      pdh_gpu_dedicated_ = gpu_ded;
      pdh_gpu_shared_ = gpu_shr;
      pdh_gpu_mem_ok_ = true;
    }

    PDH_HCOUNTER perf_counter = nullptr;
    if (PdhAddEnglishCounterW(
            query,
            L"\\Processor Information(_Total)\\% Processor Performance", 0,
            &perf_counter) == ERROR_SUCCESS) {
      pdh_cpu_perf_ = perf_counter;
      pdh_cpu_perf_ok_ = true;
    }

    // Task Manager Performance CPU % uses % Processor Utility (clamped to 100).
    PDH_HCOUNTER utility_counter = nullptr;
    if (PdhAddEnglishCounterW(
            query, L"\\Processor Information(_Total)\\% Processor Utility", 0,
            &utility_counter) == ERROR_SUCCESS) {
      pdh_cpu_utility_ = utility_counter;
      pdh_cpu_utility_ok_ = true;
    }

    // Per-logical-processor utility (same family as Task Manager Performance).
    PDH_HCOUNTER cores_counter = nullptr;
    if (PdhAddEnglishCounterW(
            query, L"\\Processor Information(*)\\% Processor Utility", 0,
            &cores_counter) == ERROR_SUCCESS) {
      pdh_cpu_cores_ = cores_counter;
      pdh_cpu_cores_ok_ = true;
    } else if (PdhAddEnglishCounterW(query, L"\\Processor(*)\\% Processor Time",
                                     0, &cores_counter) == ERROR_SUCCESS) {
      pdh_cpu_cores_ = cores_counter;
      pdh_cpu_cores_ok_ = true;
    }

    // Task Manager "Cached" = Cache + Modified + Standby lists (MS docs).
    PDH_HCOUNTER c_cache = nullptr;
    PDH_HCOUNTER c_mod = nullptr;
    PDH_HCOUNTER c_res = nullptr;
    PDH_HCOUNTER c_norm = nullptr;
    PDH_HCOUNTER c_core = nullptr;
    const bool cache_ok =
        PdhAddEnglishCounterW(query, L"\\Memory\\Cache Bytes", 0, &c_cache) ==
            ERROR_SUCCESS &&
        PdhAddEnglishCounterW(query, L"\\Memory\\Modified Page List Bytes", 0,
                              &c_mod) == ERROR_SUCCESS &&
        PdhAddEnglishCounterW(query, L"\\Memory\\Standby Cache Reserve Bytes", 0,
                              &c_res) == ERROR_SUCCESS &&
        PdhAddEnglishCounterW(query,
                              L"\\Memory\\Standby Cache Normal Priority Bytes",
                              0, &c_norm) == ERROR_SUCCESS;
    // "Core" vs "Code" naming differs by Windows build.
    const bool core_ok =
        PdhAddEnglishCounterW(query, L"\\Memory\\Standby Cache Core Bytes", 0,
                              &c_core) == ERROR_SUCCESS ||
        PdhAddEnglishCounterW(query, L"\\Memory\\Standby Cache Code Bytes", 0,
                              &c_core) == ERROR_SUCCESS;
    if (cache_ok && core_ok) {
      pdh_mem_cache_ = c_cache;
      pdh_mem_modified_ = c_mod;
      pdh_mem_standby_reserve_ = c_res;
      pdh_mem_standby_normal_ = c_norm;
      pdh_mem_standby_core_ = c_core;
      pdh_mem_cache_ok_ = true;
    }

    PDH_HCOUNTER c_compressed = nullptr;
    if (PdhAddEnglishCounterW(query, L"\\Memory\\Compressed Bytes", 0,
                              &c_compressed) == ERROR_SUCCESS) {
      pdh_mem_compressed_ = c_compressed;
      pdh_mem_compressed_ok_ = true;
    }

    PDH_HCOUNTER c_faults = nullptr;
    if (PdhAddEnglishCounterW(query, L"\\Memory\\Page Faults/sec", 0,
                              &c_faults) == ERROR_SUCCESS) {
      pdh_mem_page_faults_ = c_faults;
      pdh_mem_page_faults_ok_ = true;
    }

    PdhCollectQueryData(query);
    pdh_primed_ = true;
  } else {
    Logger::Instance().Warn("HealthMetrics",
                            "PdhOpenQuery failed; disk/GPU rates limited");
  }

  RefreshCpuBaseline();
  cpu_base_mhz_ = ReadRegistryDword(
      L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", L"~MHz");
  SYSTEM_INFO si{};
  GetSystemInfo(&si);
  cpu_logical_ = si.dwNumberOfProcessors;
  active_adapter_ = QueryActiveAdapterName();
  gpu_adapter_ = QueryPrimaryGpuAdapter();
  health_monitor_start_ms_ = 0;
  net_peak_download_bps_ = 0;
  net_peak_upload_bps_ = 0;
  net_sum_download_bps_ = 0;
  net_sum_upload_bps_ = 0;
  net_rate_samples_ = 0;
  initialized_ = true;
  Logger::Instance().Info("HealthMetrics",
                          "Collector initialized (Task Manager–aligned counters)");
  return true;
}

void HealthMetricsCollector::Shutdown() {
  std::lock_guard lock(mu_);
  if (pdh_query_ != nullptr) {
    PdhCloseQuery(static_cast<PDH_HQUERY>(pdh_query_));
    pdh_query_ = nullptr;
  }
  pdh_disk_read_ = nullptr;
  pdh_disk_write_ = nullptr;
  pdh_disk_read_all_ = nullptr;
  pdh_disk_write_all_ = nullptr;
  pdh_gpu_ = nullptr;
  pdh_gpu_dedicated_ = nullptr;
  pdh_gpu_shared_ = nullptr;
  pdh_cpu_perf_ = nullptr;
  pdh_cpu_utility_ = nullptr;
  pdh_cpu_cores_ = nullptr;
  pdh_mem_cache_ = nullptr;
  pdh_mem_modified_ = nullptr;
  pdh_mem_standby_reserve_ = nullptr;
  pdh_mem_standby_normal_ = nullptr;
  pdh_mem_standby_core_ = nullptr;
  pdh_mem_compressed_ = nullptr;
  pdh_mem_page_faults_ = nullptr;
  pdh_disk_ok_ = false;
  pdh_disk_instances_ok_ = false;
  pdh_gpu_ok_ = false;
  pdh_gpu_mem_ok_ = false;
  pdh_cpu_perf_ok_ = false;
  pdh_cpu_utility_ok_ = false;
  pdh_cpu_cores_ok_ = false;
  pdh_mem_cache_ok_ = false;
  pdh_mem_compressed_ok_ = false;
  pdh_mem_page_faults_ok_ = false;
  pdh_primed_ = false;
  initialized_ = false;
}

void HealthMetricsCollector::RefreshCpuBaseline() {
  FILETIME idle{}, kernel{}, user{};
  if (!GetSystemTimes(&idle, &kernel, &user)) {
    have_cpu_baseline_ = false;
    return;
  }
  prev_idle_ = FileTimeToU64(idle);
  prev_kernel_ = FileTimeToU64(kernel);
  prev_user_ = FileTimeToU64(user);
  have_cpu_baseline_ = true;
}

std::optional<double> HealthMetricsCollector::SampleCpuPercentFromSystemTimes() {
  FILETIME idle{}, kernel{}, user{};
  if (!GetSystemTimes(&idle, &kernel, &user)) {
    return std::nullopt;
  }
  const uint64_t idle_t = FileTimeToU64(idle);
  const uint64_t kernel_t = FileTimeToU64(kernel);
  const uint64_t user_t = FileTimeToU64(user);

  if (!have_cpu_baseline_) {
    prev_idle_ = idle_t;
    prev_kernel_ = kernel_t;
    prev_user_ = user_t;
    have_cpu_baseline_ = true;
    return std::nullopt;
  }

  const uint64_t idle_d = idle_t - prev_idle_;
  const uint64_t kernel_d = kernel_t - prev_kernel_;
  const uint64_t user_d = user_t - prev_user_;
  prev_idle_ = idle_t;
  prev_kernel_ = kernel_t;
  prev_user_ = user_t;

  const uint64_t total = kernel_d + user_d;
  if (total == 0) return 0.0;
  double busy = static_cast<double>(total - idle_d) * 100.0 /
                static_cast<double>(total);
  if (busy < 0.0) busy = 0.0;
  if (busy > 100.0) busy = 100.0;
  return busy;
}

std::optional<double> HealthMetricsCollector::SampleCpuPercent() {
  // Prefer % Processor Utility â€” same counter family as Task Manager Performance.
  if (pdh_cpu_utility_ok_ && pdh_cpu_utility_ != nullptr) {
    CollectPdhOnce();
    PDH_FMT_COUNTERVALUE val{};
    if (PdhGetFormattedCounterValue(static_cast<PDH_HCOUNTER>(pdh_cpu_utility_),
                                    PDH_FMT_DOUBLE, nullptr,
                                    &val) == ERROR_SUCCESS &&
        (val.CStatus == ERROR_SUCCESS ||
         val.CStatus == PDH_CSTATUS_VALID_DATA)) {
      double util = val.doubleValue;
      // Utility can exceed 100% under turbo; Task Manager clamps the gauge.
      if (util < 0.0) util = 0.0;
      if (util > 100.0) util = 100.0;
      return util;
    }
  }
  return SampleCpuPercentFromSystemTimes();
}

void HealthMetricsCollector::SampleMemory(ipc::HealthSample* out) {
  MEMORYSTATUSEX mem{};
  mem.dwLength = sizeof(mem);
  if (!GlobalMemoryStatusEx(&mem)) return;
  out->memory_total_bytes = mem.ullTotalPhys;
  out->memory_available_bytes = mem.ullAvailPhys;
  // Task Manager "In use" ≈ Total − Available (MS memory performance docs).
  out->memory_used_bytes = mem.ullTotalPhys - mem.ullAvailPhys;

  ULONGLONG installed_kb = 0;
  if (GetPhysicallyInstalledSystemMemory(&installed_kb) && installed_kb > 0) {
    const uint64_t installed =
        static_cast<uint64_t>(installed_kb) * 1024ULL;
    if (installed >= mem.ullTotalPhys) {
      out->has_memory_hardware_reserved = true;
      out->memory_hardware_reserved_bytes = installed - mem.ullTotalPhys;
    }
  }

  PERFORMANCE_INFORMATION pi{};
  pi.cb = sizeof(pi);
  if (GetPerformanceInfo(&pi, sizeof(pi))) {
    const SIZE_T page = pi.PageSize;
    out->has_memory_committed = true;
    out->memory_committed_bytes =
        static_cast<uint64_t>(pi.CommitTotal) * static_cast<uint64_t>(page);
    out->memory_commit_limit_bytes =
        static_cast<uint64_t>(pi.CommitLimit) * static_cast<uint64_t>(page);
    // Fallback Cached until PDH sum is available.
    out->has_memory_cached = true;
    out->memory_cached_bytes =
        static_cast<uint64_t>(pi.SystemCache) * static_cast<uint64_t>(page);
    out->has_memory_paged_pool = true;
    out->memory_paged_pool_bytes =
        static_cast<uint64_t>(pi.KernelPaged) * static_cast<uint64_t>(page);
    out->has_memory_nonpaged_pool = true;
    out->memory_nonpaged_pool_bytes =
        static_cast<uint64_t>(pi.KernelNonpaged) * static_cast<uint64_t>(page);
  }

  SampleCachedMemoryFromPdh(out);
  SampleCompressedAndFaultsFromPdh(out);
}

void HealthMetricsCollector::SampleCachedMemoryFromPdh(ipc::HealthSample* out) {
  if (!pdh_mem_cache_ok_) return;
  CollectPdhOnce();

  auto read_bytes = [&](void* counter) -> std::optional<double> {
    if (counter == nullptr) return std::nullopt;
    PDH_FMT_COUNTERVALUE val{};
    if (PdhGetFormattedCounterValue(static_cast<PDH_HCOUNTER>(counter),
                                    PDH_FMT_DOUBLE, nullptr,
                                    &val) != ERROR_SUCCESS) {
      return std::nullopt;
    }
    if (val.CStatus != ERROR_SUCCESS &&
        val.CStatus != PDH_CSTATUS_VALID_DATA) {
      return std::nullopt;
    }
    return val.doubleValue;
  };

  const auto cache = read_bytes(pdh_mem_cache_);
  const auto modified = read_bytes(pdh_mem_modified_);
  const auto reserve = read_bytes(pdh_mem_standby_reserve_);
  const auto normal = read_bytes(pdh_mem_standby_normal_);
  const auto core = read_bytes(pdh_mem_standby_core_);
  if (!cache || !modified || !reserve || !normal || !core) return;

  // Matches Task Manager "Cached" composition (MSDN memory performance info).
  const double sum =
      *cache + *modified + *reserve + *normal + *core;
  if (sum < 0.0) return;
  out->has_memory_cached = true;
  out->memory_cached_bytes = static_cast<uint64_t>(sum);
}

void HealthMetricsCollector::SampleCompressedAndFaultsFromPdh(
    ipc::HealthSample* out) {
  CollectPdhOnce();

  auto read_double = [&](void* counter) -> std::optional<double> {
    if (counter == nullptr) return std::nullopt;
    PDH_FMT_COUNTERVALUE val{};
    if (PdhGetFormattedCounterValue(static_cast<PDH_HCOUNTER>(counter),
                                    PDH_FMT_DOUBLE, nullptr,
                                    &val) != ERROR_SUCCESS) {
      return std::nullopt;
    }
    if (val.CStatus != ERROR_SUCCESS &&
        val.CStatus != PDH_CSTATUS_VALID_DATA) {
      return std::nullopt;
    }
    return val.doubleValue;
  };

  if (pdh_mem_compressed_ok_) {
    if (const auto compressed = read_double(pdh_mem_compressed_)) {
      if (*compressed >= 0.0) {
        out->has_memory_compressed = true;
        out->memory_compressed_bytes = static_cast<uint64_t>(*compressed);
      }
    }
  }

  if (pdh_mem_page_faults_ok_) {
    if (const auto faults = read_double(pdh_mem_page_faults_)) {
      if (*faults >= 0.0 && std::isfinite(*faults)) {
        out->has_memory_page_faults_per_sec = true;
        out->memory_page_faults_per_sec = *faults;
      }
    }
  }
}

void HealthMetricsCollector::SampleDiskSpace(ipc::HealthSample* out) {
  // Enumerate logical drives. Policy (issue #11):
  // - Fixed: always listed; capacity queried; included in primary summary.
  // - Removable / CD-ROM: listed only when media is present (capacity query OK).
  // - Remote/network: listed by letter; capacity NOT queried each sample
  //   (avoids SMB hangs); has_capacity=false.
  // - Unavailable roots: skipped.
  wchar_t drives[512];
  const DWORD n = GetLogicalDriveStringsW(
      static_cast<DWORD>(std::size(drives) - 1), drives);
  if (n == 0 || n >= std::size(drives)) return;

  out->volumes.clear();

  for (wchar_t* p = drives; *p != L'\0'; p += wcslen(p) + 1) {
    const UINT type = GetDriveTypeW(p);
    ipc::HealthVolume vol;
    vol.mount_point = NarrowFromWide(p);
    if (vol.mount_point.size() >= 2 && vol.mount_point[1] == ':') {
      vol.id = vol.mount_point.substr(0, 2);
    } else {
      vol.id = vol.mount_point;
    }

    switch (type) {
      case DRIVE_FIXED:
        vol.kind = ipc::HealthDriveKind::Fixed;
        vol.included_in_summary = true;
        break;
      case DRIVE_REMOVABLE:
        vol.kind = ipc::HealthDriveKind::Removable;
        break;
      case DRIVE_REMOTE:
        vol.kind = ipc::HealthDriveKind::Remote;
        break;
      case DRIVE_CDROM:
        vol.kind = ipc::HealthDriveKind::CdRom;
        break;
      case DRIVE_RAMDISK:
        vol.kind = ipc::HealthDriveKind::RamDisk;
        break;
      case DRIVE_NO_ROOT_DIR:
        continue;
      default:
        vol.kind = ipc::HealthDriveKind::Unknown;
        break;
    }

    // Skip volume info + capacity for network drives (avoid SMB/DFS hangs).
    if (vol.kind != ipc::HealthDriveKind::Remote) {
      wchar_t label[MAX_PATH] = {};
      wchar_t fs_name[MAX_PATH] = {};
      DWORD serial = 0;
      DWORD max_comp = 0;
      DWORD flags = 0;
      if (GetVolumeInformationW(p, label, MAX_PATH, &serial, &max_comp, &flags,
                                fs_name, MAX_PATH)) {
        vol.label = NarrowFromWide(label);
        vol.file_system = NarrowFromWide(fs_name);
      }

      ULARGE_INTEGER free_bytes{}, total_bytes{}, total_free{};
      if (GetDiskFreeSpaceExW(p, &free_bytes, &total_bytes, &total_free) &&
          total_bytes.QuadPart > 0) {
        vol.has_capacity = true;
        vol.total_bytes = total_bytes.QuadPart;
        vol.used_bytes = total_bytes.QuadPart - free_bytes.QuadPart;
      } else if (vol.kind == ipc::HealthDriveKind::Removable ||
                 vol.kind == ipc::HealthDriveKind::CdRom) {
        // No media â€” omit from inventory.
        continue;
      }
    }

    out->volumes.push_back(std::move(vol));
  }

  // Primary summary scalars: prefer C:, else first fixed volume with capacity.
  const ipc::HealthVolume* primary = nullptr;
  for (const auto& v : out->volumes) {
    if (!v.included_in_summary || !v.has_capacity) continue;
    if (v.id == "C:") {
      primary = &v;
      break;
    }
    if (primary == nullptr) primary = &v;
  }
  if (primary != nullptr) {
    out->disk_total_bytes = primary->total_bytes;
    out->disk_used_bytes = primary->used_bytes;
  }
}

void HealthMetricsCollector::SamplePhysicalDisks(ipc::HealthSample* out) {
  if (!pdh_disk_instances_ok_ || pdh_query_ == nullptr ||
      pdh_disk_read_all_ == nullptr || pdh_disk_write_all_ == nullptr) {
    return;
  }
  CollectPdhOnce();
  if (!pdh_collected_this_sample_) return;

  auto read_array = [](PDH_HCOUNTER counter,
                       std::map<std::wstring, double>* values) {
    values->clear();
    DWORD buffer_size = 0;
    DWORD item_count = 0;
    PDH_STATUS st = PdhGetFormattedCounterArrayW(
        counter, PDH_FMT_DOUBLE, &buffer_size, &item_count, nullptr);
    if (st != PDH_MORE_DATA && st != ERROR_SUCCESS) return;
    if (buffer_size == 0 || item_count == 0) return;
    std::vector<uint8_t> buffer(buffer_size);
    auto* items =
        reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data());
    st = PdhGetFormattedCounterArrayW(counter, PDH_FMT_DOUBLE, &buffer_size,
                                      &item_count, items);
    if (st != ERROR_SUCCESS || item_count == 0) return;
    for (DWORD i = 0; i < item_count; ++i) {
      if (items[i].szName == nullptr) continue;
      if (_wcsicmp(items[i].szName, L"_Total") == 0) continue;
      if (items[i].FmtValue.CStatus != ERROR_SUCCESS &&
          items[i].FmtValue.CStatus != PDH_CSTATUS_VALID_DATA) {
        continue;
      }
      (*values)[items[i].szName] = items[i].FmtValue.doubleValue;
    }
  };

  std::map<std::wstring, double> reads;
  std::map<std::wstring, double> writes;
  read_array(static_cast<PDH_HCOUNTER>(pdh_disk_read_all_), &reads);
  read_array(static_cast<PDH_HCOUNTER>(pdh_disk_write_all_), &writes);

  out->disks.clear();
  std::set<std::wstring> ids;
  for (const auto& kv : reads) ids.insert(kv.first);
  for (const auto& kv : writes) ids.insert(kv.first);

  for (const auto& id_w : ids) {
    ipc::HealthPhysicalDisk disk;
    disk.id = NarrowFromWide(id_w.c_str());
    disk.name = disk.id;
    const auto rit = reads.find(id_w);
    if (rit != reads.end()) {
      disk.has_read_bps = true;
      disk.read_bps = rit->second;
    }
    const auto wit = writes.find(id_w);
    if (wit != writes.end()) {
      disk.has_write_bps = true;
      disk.write_bps = wit->second;
    }
    out->disks.push_back(std::move(disk));
  }

  std::sort(out->disks.begin(), out->disks.end(),
            [](const ipc::HealthPhysicalDisk& a,
               const ipc::HealthPhysicalDisk& b) { return a.id < b.id; });
}

void HealthMetricsCollector::SampleUptime(ipc::HealthSample* out) {
  out->uptime_ms = GetTickCount64();
}

void HealthMetricsCollector::SampleNetwork(ipc::HealthSample* out) {
  PMIB_IF_TABLE2 table = nullptr;
  if (GetIfTable2(&table) != NO_ERROR || table == nullptr) {
    return;
  }

  auto is_virtual = [](const MIB_IF_ROW2& row) -> bool {
    if (row.Type == IF_TYPE_SOFTWARE_LOOPBACK) return true;
    if (row.Type == IF_TYPE_TUNNEL) return true;
    const std::wstring desc = row.Description ? row.Description : L"";
    const std::wstring alias = row.Alias ? row.Alias : L"";
    auto has = [](const std::wstring& s, const wchar_t* needle) {
      return !s.empty() &&
             wcsstr(s.c_str(), needle) != nullptr;
    };
    return has(desc, L"Virtual") || has(desc, L"Hyper-V") ||
           has(desc, L"vEthernet") || has(desc, L"VPN") ||
           has(desc, L"Teredo") || has(desc, L"ISATAP") ||
           has(desc, L"Loopback") || has(alias, L"vEthernet") ||
           has(alias, L"VPN");
  };

  // Prefer a non-virtual up adapter with the most cumulative traffic â€”
  // closest to Task Manager's default selected NIC without UI selection.
  const MIB_IF_ROW2* best = nullptr;
  uint64_t best_traffic = 0;
  const MIB_IF_ROW2* best_any = nullptr;
  uint64_t best_any_traffic = 0;

  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const MIB_IF_ROW2& row = table->Table[i];
    if (row.OperStatus != IfOperStatusUp) continue;
    if (row.Type == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    const uint64_t traffic = row.InOctets + row.OutOctets;
    if (traffic >= best_any_traffic) {
      best_any_traffic = traffic;
      best_any = &row;
    }
    if (is_virtual(row)) continue;
    if (traffic >= best_traffic) {
      best_traffic = traffic;
      best = &row;
    }
  }
  if (best == nullptr) best = best_any;
  if (best == nullptr) {
    FreeMibTable(table);
    return;
  }

  const uint64_t in_bytes = best->InOctets;
  const uint64_t out_bytes = best->OutOctets;
  active_if_index_ = best->InterfaceIndex;
  active_adapter_ = NarrowFromWide(best->Description);
  if (active_adapter_.empty()) {
    active_adapter_ = NarrowFromWide(best->Alias);
  }
  FreeMibTable(table);

  const uint64_t now_ms = GetTickCount64();
  if (!have_net_baseline_) {
    prev_net_in_ = in_bytes;
    prev_net_out_ = out_bytes;
    prev_net_tick_ms_ = now_ms;
    have_net_baseline_ = true;
    return;
  }

  const uint64_t dt_ms = now_ms - prev_net_tick_ms_;
  if (dt_ms == 0) return;

  const double dt_s = static_cast<double>(dt_ms) / 1000.0;
  // Guard against adapter switch resetting counters mid-session.
  const double down = (in_bytes >= prev_net_in_)
                          ? static_cast<double>(in_bytes - prev_net_in_) / dt_s
                          : 0.0;
  const double up = (out_bytes >= prev_net_out_)
                        ? static_cast<double>(out_bytes - prev_net_out_) / dt_s
                        : 0.0;

  prev_net_in_ = in_bytes;
  prev_net_out_ = out_bytes;
  prev_net_tick_ms_ = now_ms;

  out->has_net_download_bps = true;
  out->net_download_bps = down;
  out->has_net_upload_bps = true;
  out->net_upload_bps = up;
}

void HealthMetricsCollector::CollectPdhOnce() {
  if (pdh_query_ == nullptr || pdh_collected_this_sample_) return;
  if (PdhCollectQueryData(static_cast<PDH_HQUERY>(pdh_query_)) ==
      ERROR_SUCCESS) {
    pdh_collected_this_sample_ = true;
  }
}

void HealthMetricsCollector::SampleDiskThroughput(ipc::HealthSample* out) {
  if (!pdh_disk_ok_ || pdh_query_ == nullptr) return;
  CollectPdhOnce();
  if (!pdh_collected_this_sample_) return;

  PDH_FMT_COUNTERVALUE read_val{};
  PDH_FMT_COUNTERVALUE write_val{};
  if (PdhGetFormattedCounterValue(static_cast<PDH_HCOUNTER>(pdh_disk_read_),
                                  PDH_FMT_DOUBLE, nullptr,
                                  &read_val) == ERROR_SUCCESS &&
      (read_val.CStatus == ERROR_SUCCESS ||
       read_val.CStatus == PDH_CSTATUS_VALID_DATA)) {
    out->has_disk_read_bps = true;
    out->disk_read_bps = read_val.doubleValue;
  }
  if (PdhGetFormattedCounterValue(static_cast<PDH_HCOUNTER>(pdh_disk_write_),
                                  PDH_FMT_DOUBLE, nullptr,
                                  &write_val) == ERROR_SUCCESS &&
      (write_val.CStatus == ERROR_SUCCESS ||
       write_val.CStatus == PDH_CSTATUS_VALID_DATA)) {
    out->has_disk_write_bps = true;
    out->disk_write_bps = write_val.doubleValue;
  }
}

void HealthMetricsCollector::SampleCpuFrequency(ipc::HealthSample* out) {
  if (cpu_base_mhz_ == 0 || !pdh_cpu_perf_ok_ || pdh_cpu_perf_ == nullptr) {
    return;
  }
  CollectPdhOnce();
  if (!pdh_collected_this_sample_) return;
  PDH_FMT_COUNTERVALUE val{};
  if (PdhGetFormattedCounterValue(static_cast<PDH_HCOUNTER>(pdh_cpu_perf_),
                                  PDH_FMT_DOUBLE, nullptr,
                                  &val) != ERROR_SUCCESS) {
    return;
  }
  if (val.CStatus != ERROR_SUCCESS && val.CStatus != PDH_CSTATUS_VALID_DATA) {
    return;
  }
  // % Processor Performance is relative to base clock.
  const double mhz =
      static_cast<double>(cpu_base_mhz_) * (val.doubleValue / 100.0);
  if (mhz <= 0.0) return;
  out->has_cpu_current_mhz = true;
  out->cpu_current_mhz = mhz;
}

void HealthMetricsCollector::SampleGpuPercent(ipc::HealthSample* out) {
  if (!pdh_gpu_ok_ || pdh_query_ == nullptr || pdh_gpu_ == nullptr) return;
  CollectPdhOnce();
  if (!pdh_collected_this_sample_) return;

  DWORD buffer_size = 0;
  DWORD item_count = 0;
  PDH_STATUS st = PdhGetFormattedCounterArrayW(
      static_cast<PDH_HCOUNTER>(pdh_gpu_), PDH_FMT_DOUBLE, &buffer_size,
      &item_count, nullptr);
  if (st != PDH_MORE_DATA && st != ERROR_SUCCESS) return;
  if (buffer_size == 0 || item_count == 0) return;

  std::vector<uint8_t> buffer(buffer_size);
  auto* items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data());
  st = PdhGetFormattedCounterArrayW(static_cast<PDH_HCOUNTER>(pdh_gpu_),
                                    PDH_FMT_DOUBLE, &buffer_size, &item_count,
                                    items);
  if (st != ERROR_SUCCESS || item_count == 0) return;

  // Task Manager overall GPU % â‰ˆ highest engine utilization.
  double max_util = 0.0;
  bool any = false;
  for (DWORD i = 0; i < item_count; ++i) {
    if (items[i].FmtValue.CStatus != ERROR_SUCCESS &&
        items[i].FmtValue.CStatus != PDH_CSTATUS_VALID_DATA) {
      continue;
    }
    any = true;
    max_util = (std::max)(max_util, items[i].FmtValue.doubleValue);
  }
  if (!any) return;
  if (max_util < 0.0) max_util = 0.0;
  if (max_util > 100.0) max_util = 100.0;
  out->has_gpu_percent = true;
  out->gpu_percent = max_util;
}

void HealthMetricsCollector::SampleCpuCores(ipc::HealthSample* out) {
  if (!pdh_cpu_cores_ok_ || pdh_cpu_cores_ == nullptr || pdh_query_ == nullptr) {
    return;
  }
  CollectPdhOnce();
  if (!pdh_collected_this_sample_) return;

  DWORD buffer_size = 0;
  DWORD item_count = 0;
  PDH_STATUS st = PdhGetFormattedCounterArrayW(
      static_cast<PDH_HCOUNTER>(pdh_cpu_cores_), PDH_FMT_DOUBLE, &buffer_size,
      &item_count, nullptr);
  if (st != PDH_MORE_DATA && st != ERROR_SUCCESS) return;
  if (buffer_size == 0 || item_count == 0) return;

  std::vector<uint8_t> buffer(buffer_size);
  auto* items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data());
  st = PdhGetFormattedCounterArrayW(static_cast<PDH_HCOUNTER>(pdh_cpu_cores_),
                                    PDH_FMT_DOUBLE, &buffer_size, &item_count,
                                    items);
  if (st != ERROR_SUCCESS || item_count == 0) return;

  // Processor Information instances are "0,0", "0,1", â€¦ â€” sort by name.
  struct CoreVal {
    std::wstring name;
    double value = 0;
  };
  std::vector<CoreVal> cores;
  for (DWORD i = 0; i < item_count; ++i) {
    if (items[i].szName == nullptr) continue;
    if (_wcsicmp(items[i].szName, L"_Total") == 0) continue;
    if (items[i].FmtValue.CStatus != ERROR_SUCCESS &&
        items[i].FmtValue.CStatus != PDH_CSTATUS_VALID_DATA) {
      continue;
    }
    CoreVal cv;
    cv.name = items[i].szName;
    cv.value = items[i].FmtValue.doubleValue;
    if (cv.value < 0) cv.value = 0;
    if (cv.value > 100) cv.value = 100;
    cores.push_back(std::move(cv));
  }
  std::sort(cores.begin(), cores.end(),
            [](const CoreVal& a, const CoreVal& b) { return a.name < b.name; });
  out->cpu_core_percent.clear();
  out->cpu_core_percent.reserve(cores.size());
  for (const auto& c : cores) {
    out->cpu_core_percent.push_back(c.value);
  }
}

void HealthMetricsCollector::SampleGpuAdapterMemory(ipc::HealthSample* out) {
  if (!pdh_gpu_mem_ok_ || pdh_gpu_dedicated_ == nullptr ||
      pdh_gpu_shared_ == nullptr) {
    return;
  }
  CollectPdhOnce();
  if (!pdh_collected_this_sample_) return;

  auto read_luid_bytes = [&](void* counter) -> std::optional<uint64_t> {
    DWORD buffer_size = 0;
    DWORD item_count = 0;
    PDH_STATUS st = PdhGetFormattedCounterArrayW(
        static_cast<PDH_HCOUNTER>(counter), PDH_FMT_DOUBLE, &buffer_size,
        &item_count, nullptr);
    if (st != PDH_MORE_DATA && st != ERROR_SUCCESS) return std::nullopt;
    if (buffer_size == 0 || item_count == 0) return std::nullopt;
    std::vector<uint8_t> buffer(buffer_size);
    auto* items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data());
    st = PdhGetFormattedCounterArrayW(static_cast<PDH_HCOUNTER>(counter),
                                      PDH_FMT_DOUBLE, &buffer_size, &item_count,
                                      items);
    if (st != ERROR_SUCCESS || item_count == 0) return std::nullopt;
    double best = -1.0;
    for (DWORD i = 0; i < item_count; ++i) {
      if (items[i].FmtValue.CStatus != ERROR_SUCCESS &&
          items[i].FmtValue.CStatus != PDH_CSTATUS_VALID_DATA) {
        continue;
      }
      if (gpu_adapter_.has_luid && !gpu_adapter_.luid_pdh_token.empty()) {
        if (!GpuInstanceMatchesLuid(items[i].szName,
                                    gpu_adapter_.luid_pdh_token)) {
          continue;
        }
      }
      best = (std::max)(best, items[i].FmtValue.doubleValue);
    }
    if (best < 0.0) return std::nullopt;
    return static_cast<uint64_t>(best);
  };

  if (const auto dedicated = read_luid_bytes(pdh_gpu_dedicated_)) {
    out->has_gpu_dedicated_used = true;
    out->gpu_dedicated_used_bytes = *dedicated;
  }
  if (const auto shared = read_luid_bytes(pdh_gpu_shared_)) {
    out->has_gpu_shared_used = true;
    out->gpu_shared_used_bytes = *shared;
  }
}

void HealthMetricsCollector::SampleTopGpuFromPdh(ipc::HealthSample* out) {
  if (!pdh_gpu_ok_ || pdh_gpu_ == nullptr) return;
  CollectPdhOnce();
  if (!pdh_collected_this_sample_) return;

  DWORD buffer_size = 0;
  DWORD item_count = 0;
  PDH_STATUS st = PdhGetFormattedCounterArrayW(
      static_cast<PDH_HCOUNTER>(pdh_gpu_), PDH_FMT_DOUBLE, &buffer_size,
      &item_count, nullptr);
  if (st != PDH_MORE_DATA && st != ERROR_SUCCESS) return;
  if (buffer_size == 0 || item_count == 0) return;

  std::vector<uint8_t> buffer(buffer_size);
  auto* items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data());
  st = PdhGetFormattedCounterArrayW(static_cast<PDH_HCOUNTER>(pdh_gpu_),
                                    PDH_FMT_DOUBLE, &buffer_size, &item_count,
                                    items);
  if (st != ERROR_SUCCESS || item_count == 0) return;

  struct GpuPidAgg {
    double util = 0;
    std::string engine;
  };
  std::map<uint32_t, GpuPidAgg> by_pid;
  for (DWORD i = 0; i < item_count; ++i) {
    if (items[i].FmtValue.CStatus != ERROR_SUCCESS &&
        items[i].FmtValue.CStatus != PDH_CSTATUS_VALID_DATA) {
      continue;
    }
    if (gpu_adapter_.has_luid && !gpu_adapter_.luid_pdh_token.empty() &&
        !GpuInstanceMatchesLuid(items[i].szName, gpu_adapter_.luid_pdh_token)) {
      continue;
    }
    const uint32_t pid = ParsePidFromGpuInstance(items[i].szName);
    if (pid == 0) continue;
    const double util = items[i].FmtValue.doubleValue;
    auto& agg = by_pid[pid];
    if (util >= agg.util) {
      agg.util = util;
      std::wstring name = items[i].szName ? items[i].szName : L"";
      const wchar_t* eng = wcsstr(name.c_str(), L"engtype_");
      if (eng != nullptr) {
        eng += 8;
        std::wstring eng_w(eng);
        // Trim trailing junk after engine type token.
        const auto cut = eng_w.find_first_of(L" _");
        if (cut != std::wstring::npos) eng_w.resize(cut);
        agg.engine = NarrowFromWide(eng_w.c_str());
      }
    }
  }
  if (by_pid.empty()) return;

  // Prefer SPI inventory names when present in prev_inventory_.
  std::unordered_map<uint32_t, std::string> names_by_pid;
  for (const auto& [key, row] : prev_inventory_) {
    if (!row.name.empty()) names_by_pid[key.pid] = row.name;
  }

  std::vector<ipc::HealthProcessEntry> entries;
  for (const auto& [pid, agg] : by_pid) {
    ipc::HealthProcessEntry e;
    e.pid = pid;
    e.has_gpu_percent = true;
    e.gpu_percent = agg.util;
    e.gpu_engine = agg.engine;
    e.path = ResolveProcessExecutablePath(pid, {});
    if (!e.path.empty()) {
      const auto slash = e.path.find_last_of("\\/");
      e.name = slash == std::string::npos ? e.path : e.path.substr(slash + 1);
    }
    if (e.name.empty()) {
      const auto it = names_by_pid.find(pid);
      if (it != names_by_pid.end()) e.name = it->second;
    }
    if (e.name.empty()) e.name = "pid_" + std::to_string(pid);
    entries.push_back(std::move(e));
  }
  KeepTopN(&entries, kTopProcessLimit,
           [](const ipc::HealthProcessEntry& e) { return e.gpu_percent; });
  FillExecutablePaths(&entries);
  out->top_gpu = std::move(entries);
}

void HealthMetricsCollector::SampleNetworkAddresses(ipc::HealthSample* out) {
  ULONG flags = GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_INCLUDE_PREFIX;
  ULONG size = 0;
  GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, nullptr, &size);
  if (size == 0) return;
  std::vector<uint8_t> buf(size);
  auto* addrs = reinterpret_cast<IP_ADAPTER_ADDRESSES_LH*>(buf.data());
  if (GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, addrs, &size) !=
      NO_ERROR) {
    return;
  }

  IP_ADAPTER_ADDRESSES_LH* best = nullptr;
  IP_ADAPTER_ADDRESSES_LH* fallback = nullptr;
  for (auto* a = addrs; a != nullptr; a = a->Next) {
    if (a->OperStatus != IfOperStatusUp) continue;
    if (a->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    if (fallback == nullptr) fallback = a;
    const std::string desc = NarrowFromWide(a->Description);
    const std::string friendly = NarrowFromWide(a->FriendlyName);
    if (!active_adapter_.empty() &&
        (desc == active_adapter_ || friendly == active_adapter_ ||
         desc.find(active_adapter_) != std::string::npos ||
         active_adapter_.find(desc) != std::string::npos ||
         friendly.find(active_adapter_) != std::string::npos ||
         active_adapter_.find(friendly) != std::string::npos)) {
      best = a;
      break;
    }
  }
  if (best == nullptr) best = fallback;
  if (best == nullptr) return;

  for (auto* u = best->FirstUnicastAddress; u != nullptr; u = u->Next) {
    if (u->Address.lpSockaddr == nullptr) continue;
    if (u->Address.lpSockaddr->sa_family == AF_INET && out->ipv4.empty()) {
      auto* sin = reinterpret_cast<sockaddr_in*>(u->Address.lpSockaddr);
      char host[INET_ADDRSTRLEN]{};
      if (InetNtopA(AF_INET, &sin->sin_addr, host, sizeof(host)) != nullptr) {
        out->ipv4 = host;
      }
    } else if (u->Address.lpSockaddr->sa_family == AF_INET6 &&
               out->ipv6.empty()) {
      auto* sin6 = reinterpret_cast<sockaddr_in6*>(u->Address.lpSockaddr);
      char host[INET6_ADDRSTRLEN]{};
      if (InetNtopA(AF_INET6, &sin6->sin6_addr, host, sizeof(host)) !=
          nullptr) {
        if (strncmp(host, "fe80", 4) == 0) continue;
        out->ipv6 = host;
      }
    }
  }
  // Fallback: allow link-local IPv6 if nothing else.
  if (out->ipv6.empty()) {
    for (auto* u = best->FirstUnicastAddress; u != nullptr; u = u->Next) {
      if (u->Address.lpSockaddr == nullptr) continue;
      if (u->Address.lpSockaddr->sa_family != AF_INET6) continue;
      auto* sin6 = reinterpret_cast<sockaddr_in6*>(u->Address.lpSockaddr);
      char host[INET6_ADDRSTRLEN]{};
      if (InetNtopA(AF_INET6, &sin6->sin6_addr, host, sizeof(host)) !=
          nullptr) {
        out->ipv6 = host;
        break;
      }
    }
  }

  for (auto* g = best->FirstGatewayAddress; g != nullptr; g = g->Next) {
    if (g->Address.lpSockaddr == nullptr) continue;
    if (g->Address.lpSockaddr->sa_family == AF_INET) {
      auto* sin = reinterpret_cast<sockaddr_in*>(g->Address.lpSockaddr);
      char host[INET_ADDRSTRLEN]{};
      if (InetNtopA(AF_INET, &sin->sin_addr, host, sizeof(host)) != nullptr) {
        out->gateway = host;
        break;
      }
    }
  }

  FIXED_INFO* fixed = nullptr;
  ULONG fixed_len = 0;
  if (GetNetworkParams(nullptr, &fixed_len) == ERROR_BUFFER_OVERFLOW) {
    std::vector<uint8_t> fixed_buf(fixed_len);
    fixed = reinterpret_cast<FIXED_INFO*>(fixed_buf.data());
    if (GetNetworkParams(fixed, &fixed_len) == ERROR_SUCCESS) {
      out->dns = fixed->DnsServerList.IpAddress.String;
      if (fixed->DnsServerList.Next != nullptr) {
        out->dns += ", ";
        out->dns += fixed->DnsServerList.Next->IpAddress.String;
      }
    }
  }
}

void HealthMetricsCollector::SamplePerProcessNetwork(
    std::unordered_map<uint32_t, uint64_t>* tcp_bytes_by_pid) {
  if (tcp_bytes_by_pid == nullptr) return;
  tcp_bytes_by_pid->clear();

  // Per-process network rates are intentionally not collected here.
  // GetPerTcpConnectionEStats is unsuitable for PulseService under
  // LocalService: MSDN requires SetPerTcpConnectionEStats enable-first,
  // admin rights, and checking EnableCollection — otherwise ROD data is
  // undefined. Runtime proved multi-GB/s garbage rates on the wire.
  // See docs/architecture/24-health-metrics-task-manager.md (network APIs).
  // Future: ETW Microsoft-Windows-TCPIP / Win32 Networking (PID-tagged).
  (void)tcp_bytes_by_pid;
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int wlen =
      MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (wlen <= 1) return {};
  std::wstring out(static_cast<size_t>(wlen - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), wlen);
  return out;
}

std::string QueryVersionString(const std::wstring& wpath, const wchar_t* key) {
  DWORD dummy = 0;
  const DWORD ver_size = GetFileVersionInfoSizeW(wpath.c_str(), &dummy);
  if (ver_size == 0) return {};
  std::vector<uint8_t> ver(ver_size);
  if (!GetFileVersionInfoW(wpath.c_str(), 0, ver_size, ver.data())) return {};

  struct LANGANDCODEPAGE {
    WORD wLanguage;
    WORD wCodePage;
  };
  LANGANDCODEPAGE* translate = nullptr;
  UINT translate_len = 0;
  if (!VerQueryValueW(ver.data(), L"\\VarFileInfo\\Translation",
                      reinterpret_cast<LPVOID*>(&translate), &translate_len) ||
      translate == nullptr || translate_len < sizeof(LANGANDCODEPAGE)) {
    return {};
  }
  wchar_t sub[96];
  swprintf_s(sub, L"\\StringFileInfo\\%04x%04x\\%s", translate[0].wLanguage,
             translate[0].wCodePage, key);
  wchar_t* value = nullptr;
  UINT value_len = 0;
  if (!VerQueryValueW(ver.data(), sub, reinterpret_cast<LPVOID*>(&value),
                      &value_len) ||
      value == nullptr || value_len <= 1) {
    return {};
  }
  return TrimCopy(NarrowFromWide(value));
}

void FillVersionStrings(const std::string& path, ipc::ProcessDetails* d) {
  const std::wstring wpath = Utf8ToWide(path);
  if (wpath.empty()) return;
  const std::string company = QueryVersionString(wpath, L"CompanyName");
  if (!company.empty()) {
    d->company = company;
    d->has_company = true;
  }
  std::string product = QueryVersionString(wpath, L"FileDescription");
  if (product.empty()) {
    product = QueryVersionString(wpath, L"ProductName");
  }
  if (!product.empty()) {
    d->product_name = product;
    d->has_product_name = true;
  }
}

using NtQueryInformationProcessFn = LONG(WINAPI*)(HANDLE, ULONG, PVOID, ULONG,
                                                   PULONG);

NtQueryInformationProcessFn ResolveNtQip() {
  static auto fn = reinterpret_cast<NtQueryInformationProcessFn>(
      GetProcAddress(GetModuleHandleW(L"ntdll.dll"),
                     "NtQueryInformationProcess"));
  return fn;
}

void FillCommandLine(HANDLE h, ipc::ProcessDetails* d) {
  auto NtQip = ResolveNtQip();
  constexpr ULONG kProcessCommandLineInformation = 70;
  if (NtQip == nullptr) return;
  ULONG needed = 0;
  NtQip(h, kProcessCommandLineInformation, nullptr, 0, &needed);
  if (needed == 0 || needed >= 64 * 1024) return;
  std::vector<uint8_t> buf(needed);
  const LONG st =
      NtQip(h, kProcessCommandLineInformation, buf.data(), needed, &needed);
  if (st < 0 || needed < sizeof(PulseUnicodeString)) return;
  auto* us = reinterpret_cast<PulseUnicodeString*>(buf.data());
  if (us->Buffer == nullptr || us->Length == 0) return;
  std::wstring w(us->Buffer, us->Length / sizeof(wchar_t));
  d->command_line = NarrowFromWide(w.c_str());
  d->has_command_line = !d->command_line.empty();
}

void FillArchitecture(HANDLE h, ipc::ProcessDetails* d) {
  using IsWow64Process2Fn = BOOL(WINAPI*)(HANDLE, USHORT*, USHORT*);
  static auto IsWow64Process2Ptr = reinterpret_cast<IsWow64Process2Fn>(
      GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "IsWow64Process2"));
  if (IsWow64Process2Ptr != nullptr) {
    USHORT process_machine = 0;
    USHORT native_machine = 0;
    if (IsWow64Process2Ptr(h, &process_machine, &native_machine)) {
      // IMAGE_FILE_MACHINE_UNKNOWN (0) means not WOW64 — native process.
      const USHORT machine =
          process_machine == 0 ? native_machine : process_machine;
      switch (machine) {
        case 0x014c:  // IMAGE_FILE_MACHINE_I386
          d->architecture = "x86";
          d->has_architecture = true;
          return;
        case 0x8664:  // IMAGE_FILE_MACHINE_AMD64
          d->architecture = "x64";
          d->has_architecture = true;
          return;
        case 0xAA64:  // IMAGE_FILE_MACHINE_ARM64
          d->architecture = "ARM64";
          d->has_architecture = true;
          return;
        default:
          break;
      }
    }
  }

  BOOL wow64 = FALSE;
  if (IsWow64Process(h, &wow64)) {
    d->architecture = wow64 ? "x86" : "x64";
    d->has_architecture = true;
  }
}

std::string IntegrityLevelName(DWORD rid) {
  if (rid >= 0x00005000) return "Protected";
  if (rid >= 0x00004000) return "System";
  if (rid >= 0x00003000) return "High";
  if (rid >= 0x00002100) return "Medium Plus";
  if (rid >= 0x00002000) return "Medium";
  if (rid >= 0x00001000) return "Low";
  return "Untrusted";
}

void FillTokenInfo(HANDLE process, ipc::ProcessDetails* d) {
  HANDLE token = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &token) || token == nullptr) {
    return;
  }

  TOKEN_ELEVATION elevation{};
  DWORD ret = 0;
  if (GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation),
                          &ret)) {
    d->has_elevated = true;
    d->elevated = elevation.TokenIsElevated != 0;
  }

  DWORD needed = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &needed);
  if (needed > 0 && needed < 4096) {
    std::vector<uint8_t> buf(needed);
    if (GetTokenInformation(token, TokenUser, buf.data(), needed, &needed)) {
      auto* user = reinterpret_cast<TOKEN_USER*>(buf.data());
      wchar_t name[256];
      wchar_t domain[256];
      DWORD name_len = 256;
      DWORD domain_len = 256;
      SID_NAME_USE use{};
      if (LookupAccountSidW(nullptr, user->User.Sid, name, &name_len, domain,
                            &domain_len, &use)) {
        std::string account = NarrowFromWide(domain);
        if (!account.empty()) account += "\\";
        account += NarrowFromWide(name);
        if (!account.empty()) {
          d->user = account;
          d->has_user = true;
        }
      }
    }
  }

  needed = 0;
  GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &needed);
  if (needed > 0 && needed < 1024) {
    std::vector<uint8_t> buf(needed);
    if (GetTokenInformation(token, TokenIntegrityLevel, buf.data(), needed,
                            &needed)) {
      auto* til = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buf.data());
      if (til->Label.Sid != nullptr) {
        const DWORD rid = *GetSidSubAuthority(
            til->Label.Sid, static_cast<DWORD>(*GetSidSubAuthorityCount(
                                                   til->Label.Sid) -
                                               1));
        d->integrity_level = IntegrityLevelName(rid);
        d->has_integrity_level = !d->integrity_level.empty();
      }
    }
  }

  CloseHandle(token);
}

static bool QueryIsProcessCritical(uint32_t pid, bool* out_critical) {
  *out_critical = false;
  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (h == nullptr) return false;
  BOOL critical = FALSE;
  const BOOL ok = IsProcessCritical(h, &critical);
  CloseHandle(h);
  if (!ok) return false;
  *out_critical = critical != FALSE;
  return true;
}

static bool LooksLikeWindowsProcessName(const std::string& name) {
  const std::string lower = AsciiLowerCopy(name);
  static constexpr const char* kNames[] = {
      "system",           "smss.exe",        "csrss.exe",
      "wininit.exe",      "services.exe",    "lsass.exe",
      "winlogon.exe",     "svchost.exe",     "dwm.exe",
      "fontdrvhost.exe",  "memory compression",
  };
  for (const char* n : kNames) {
    if (lower == n) return true;
  }
  return false;
}

void HealthMetricsCollector::SampleProcessesCombined(
    ipc::HealthSample* sample_out,
    ipc::HealthProcessInventoryUpdate* inv_out) {
  // NtQuerySystemInformation(SystemProcessInformation) — same family as
  // System Informer / Task Manager process lists. Metrics need no handles.
  auto* NtQuery = ResolveNtQuerySystemInformation();
  if (NtQuery == nullptr) {
    Logger::Instance().Warn("HealthMetrics",
                            "NtQuerySystemInformation unavailable");
    return;
  }

  const uint64_t now_ms = GetTickCount64();
  const double dt_s = have_proc_baseline_
                          ? (std::max)(0.001, (now_ms - prev_proc_tick_ms_) /
                                                  1000.0)
                          : 1.0;
  const uint32_t logical = (std::max)(1u, cpu_logical_);
  const ProcessCpuMode cpu_mode = process_cpu_.mode();

  ULONG needed = 0;
  LONG st = NtQuery(kSystemProcessInformation, nullptr, 0, &needed);
  if (st != kStatusInfoLengthMismatch && st != kStatusSuccess) {
    Logger::Instance().Warn(
        "HealthMetrics",
        "NtQuerySystemInformation size probe failed status=" +
            std::to_string(static_cast<unsigned long>(st)));
    return;
  }

  std::vector<uint8_t> buffer;
  for (int attempt = 0; attempt < 6; ++attempt) {
    if (needed < sizeof(PulseSystemProcessInformation)) {
      needed = static_cast<ULONG>(sizeof(PulseSystemProcessInformation) * 64);
    }
    const ULONG alloc = needed + (needed / 4) + 4096;
    buffer.assign(alloc, 0);
    needed = 0;
    st = NtQuery(kSystemProcessInformation, buffer.data(), alloc, &needed);
    if (st == kStatusSuccess) break;
    if (st != kStatusInfoLengthMismatch) {
      Logger::Instance().Warn(
          "HealthMetrics",
          "NtQuerySystemInformation failed status=" +
              std::to_string(static_cast<unsigned long>(st)));
      return;
    }
  }
  if (st != kStatusSuccess || buffer.empty()) return;

  std::unordered_map<uint32_t, uint64_t> tcp_bytes_by_pid;
  SamplePerProcessNetwork(&tcp_bytes_by_pid);

  std::optional<uint64_t> idle_cycle_delta;
  if (cpu_mode == ProcessCpuMode::CycleBased) {
    idle_cycle_delta = idle_cycles_.SampleDelta();
  }

  struct RowBuild {
    ProcessKey key;
    ipc::HealthProcessEntry entry;
    uint64_t cpu_100ns = 0;
    uint64_t cycle_time = 0;
    uint64_t io_bytes = 0;
    uint64_t tcp_bytes = 0;
    uint32_t parent_pid = 0;
  };

  std::vector<RowBuild> rows;
  rows.reserve(256);
  uint64_t sum_cycle_deltas = 0;

  size_t offset = 0;
  for (;;) {
    if (offset + sizeof(PulseSystemProcessInformation) > buffer.size()) break;
    const auto* info = reinterpret_cast<const PulseSystemProcessInformation*>(
        buffer.data() + offset);
    const uint32_t pid = static_cast<uint32_t>(
        reinterpret_cast<uintptr_t>(info->UniqueProcessId));
    if (pid != 0) {
      RowBuild row;
      row.key.pid = pid;
      row.key.create_time_100ns =
          static_cast<uint64_t>(info->CreateTime.QuadPart);
      row.cpu_100ns = static_cast<uint64_t>(info->KernelTime.QuadPart) +
                      static_cast<uint64_t>(info->UserTime.QuadPart);
      row.cycle_time = static_cast<uint64_t>(info->CycleTime);
      row.io_bytes = static_cast<uint64_t>(info->ReadTransferCount.QuadPart) +
                     static_cast<uint64_t>(info->WriteTransferCount.QuadPart) +
                     static_cast<uint64_t>(info->OtherTransferCount.QuadPart);
      row.parent_pid = static_cast<uint32_t>(
          reinterpret_cast<uintptr_t>(info->InheritedFromUniqueProcessId));
      const auto tcp_it = tcp_bytes_by_pid.find(pid);
      if (tcp_it != tcp_bytes_by_pid.end()) row.tcp_bytes = tcp_it->second;

      row.entry.pid = pid;
      row.entry.name = ProcessNameFromSpi(*info);
      row.entry.thread_count = info->NumberOfThreads;
      row.entry.handle_count = info->HandleCount;
      row.entry.has_create_time = info->CreateTime.QuadPart > 0;
      row.entry.create_time_unix_ms =
          FileTimeToUnixMs(info->CreateTime.QuadPart);

      const uint64_t private_ws =
          static_cast<uint64_t>(info->WorkingSetPrivateSize.QuadPart);
      row.entry.has_memory_bytes = true;
      row.entry.memory_bytes =
          private_ws > 0 ? private_ws
                         : static_cast<uint64_t>(info->WorkingSetSize);

      row.entry.has_working_set_bytes = true;
      row.entry.working_set_bytes =
          static_cast<uint64_t>(info->WorkingSetSize);
      row.entry.has_commit_bytes = true;
      row.entry.commit_bytes = static_cast<uint64_t>(info->PagefileUsage);
      row.entry.has_paged_pool_bytes = true;
      row.entry.paged_pool_bytes =
          static_cast<uint64_t>(info->QuotaPagedPoolUsage);
      row.entry.has_nonpaged_pool_bytes = true;
      row.entry.nonpaged_pool_bytes =
          static_cast<uint64_t>(info->QuotaNonPagedPoolUsage);

      bool critical = false;
      if (QueryIsProcessCritical(pid, &critical)) {
        row.entry.has_is_critical = true;
        row.entry.is_critical = critical;
      } else if (LooksLikeWindowsProcessName(row.entry.name)) {
        row.entry.has_is_critical = true;
        row.entry.is_critical = true;
      }

      if (have_proc_baseline_ && cpu_mode == ProcessCpuMode::CycleBased) {
        const auto prev = prev_proc_cpu_.find(row.key);
        if (prev != prev_proc_cpu_.end() &&
            row.cycle_time >= prev->second.cycle_time) {
          sum_cycle_deltas += row.cycle_time - prev->second.cycle_time;
        }
      }

      rows.push_back(std::move(row));
    }
    if (info->NextEntryOffset == 0) break;
    offset += info->NextEntryOffset;
  }

  uint64_t total_cycle_delta = sum_cycle_deltas;
  if (idle_cycle_delta.has_value()) {
    total_cycle_delta += *idle_cycle_delta;
  }

  std::unordered_map<ProcessKey, ProcCpuPrev, ProcessKeyHash> next_cpu;
  std::unordered_map<ProcessKey, ProcIoPrev, ProcessKeyHash> next_io;
  std::unordered_map<ProcessKey, uint64_t, ProcessKeyHash> next_tcp;
  std::unordered_map<ProcessKey, InvRowPrev, ProcessKeyHash> next_inv;
  std::unordered_map<ProcessKey, ipc::HealthProcessEntry, ProcessKeyHash>
      current;
  std::unordered_map<uint32_t, uint64_t> next_pid_create;
  std::vector<ipc::HealthProcessEntry> cpu_rows;
  std::vector<ipc::HealthProcessEntry> mem_rows;
  std::vector<ipc::HealthProcessEntry> disk_rows;

  constexpr uint64_t kFullResyncIntervalMs = 30000;
  const bool full =
      force_full_resync_ || last_full_resync_ms_ == 0 ||
      (now_ms - last_full_resync_ms_) >= kFullResyncIntervalMs;
  constexpr double kMaxPlausibleBps = 40.0 * 1024 * 1024 * 1024;

  for (auto& row : rows) {
    const ProcessKey& key = row.key;
    next_cpu[key] = ProcCpuPrev{row.cpu_100ns, row.cycle_time};
    next_io[key] = ProcIoPrev{row.io_bytes};
    next_tcp[key] = row.tcp_bytes;
    next_pid_create[key.pid] = key.create_time_100ns;

    auto& e = row.entry;

    if (have_proc_baseline_) {
      const auto cpu_it = prev_proc_cpu_.find(key);
      if (cpu_it != prev_proc_cpu_.end()) {
        if (cpu_mode == ProcessCpuMode::CycleBased && total_cycle_delta > 0 &&
            row.cycle_time >= cpu_it->second.cycle_time) {
          const uint64_t d = row.cycle_time - cpu_it->second.cycle_time;
          if (auto pct = ProcessCpuCalculator::CycleBasedPercent(
                  d, total_cycle_delta)) {
            e.has_cpu_percent = true;
            e.cpu_percent = *pct;
          }
        } else if (cpu_mode == ProcessCpuMode::TimeBased &&
                   row.cpu_100ns >= cpu_it->second.cpu_100ns) {
          const uint64_t d = row.cpu_100ns - cpu_it->second.cpu_100ns;
          if (auto pct = ProcessCpuCalculator::TimeBasedPercent(d, dt_s,
                                                                logical)) {
            e.has_cpu_percent = true;
            e.cpu_percent = *pct;
          }
        }
      }

      const auto io_it = prev_proc_io_.find(key);
      if (io_it != prev_proc_io_.end() && row.io_bytes >= io_it->second.bytes) {
        const double bps =
            static_cast<double>(row.io_bytes - io_it->second.bytes) / dt_s;
        if (bps > 0.0 && bps <= kMaxPlausibleBps && std::isfinite(bps)) {
          e.has_disk_bps = true;
          e.disk_bps = bps;
        }
      }

      const auto net_it = prev_tcp_bytes_.find(key);
      if (net_it != prev_tcp_bytes_.end() && row.tcp_bytes >= net_it->second) {
        const double bps =
            static_cast<double>(row.tcp_bytes - net_it->second) / dt_s;
        if (bps >= 1.0 && bps <= kMaxPlausibleBps && std::isfinite(bps)) {
          e.has_net_bps = true;
          e.net_bps = bps;
        }
      }
    }

    const bool is_new = prev_inventory_.find(key) == prev_inventory_.end();
    if (full || is_new) {
      e.path = ResolveProcessExecutablePath(key.pid, e.name);
    } else {
      e.path = prev_inventory_[key].path;
    }

    if (e.has_cpu_percent && e.cpu_percent > 0.01) cpu_rows.push_back(e);
    if (e.has_disk_bps && e.disk_bps > 1024.0) disk_rows.push_back(e);
    if (e.memory_bytes > 1024 * 1024) mem_rows.push_back(e);

    InvRowPrev snap;
    snap.key = key;
    snap.name = e.name;
    snap.cpu_percent = e.cpu_percent;
    snap.has_cpu = e.has_cpu_percent;
    snap.memory_bytes = e.memory_bytes;
    snap.working_set_bytes = e.working_set_bytes;
    snap.commit_bytes = e.commit_bytes;
    snap.paged_pool_bytes = e.paged_pool_bytes;
    snap.nonpaged_pool_bytes = e.nonpaged_pool_bytes;
    snap.disk_bps = e.disk_bps;
    snap.has_disk = e.has_disk_bps;
    snap.net_bps = e.net_bps;
    snap.has_net = e.has_net_bps;
    snap.thread_count = e.thread_count;
    snap.handle_count = e.handle_count;
    snap.path = e.path;
    snap.is_critical = e.is_critical;
    snap.has_is_critical = e.has_is_critical;
    snap.parent_pid = row.parent_pid;
    next_inv[key] = snap;
    current[key] = std::move(e);
  }

  prev_proc_cpu_ = std::move(next_cpu);
  prev_proc_io_ = std::move(next_io);
  prev_tcp_bytes_ = std::move(next_tcp);
  prev_pid_create_time_ = std::move(next_pid_create);
  prev_proc_tick_ms_ = now_ms;
  have_proc_baseline_ = true;

  KeepTopN(&cpu_rows, kTopProcessLimit,
           [](const ipc::HealthProcessEntry& e) { return e.cpu_percent; });
  KeepTopN(&mem_rows, kTopProcessLimit,
           [](const ipc::HealthProcessEntry& e) {
             return static_cast<double>(e.memory_bytes);
           });
  KeepTopN(&disk_rows, kTopProcessLimit,
           [](const ipc::HealthProcessEntry& e) { return e.disk_bps; });
  FillExecutablePaths(&cpu_rows);
  FillExecutablePaths(&mem_rows);
  FillExecutablePaths(&disk_rows);
  if (sample_out != nullptr) {
    sample_out->top_cpu = std::move(cpu_rows);
    sample_out->top_memory = std::move(mem_rows);
    sample_out->top_disk = std::move(disk_rows);
    sample_out->top_network.clear();
  }

  if (inv_out != nullptr) {
    inv_out->seq = ++inventory_seq_;
    inv_out->full_resync = full;
    inv_out->upserts.clear();
    inv_out->removed_pids.clear();

    auto changed = [](const InvRowPrev& a, const ipc::HealthProcessEntry& b) {
      if (a.name != b.name) return true;
      if (a.thread_count != b.thread_count || a.handle_count != b.handle_count)
        return true;
      if (a.memory_bytes != b.memory_bytes) return true;
      if (a.working_set_bytes != b.working_set_bytes) return true;
      if (a.commit_bytes != b.commit_bytes) return true;
      if (a.paged_pool_bytes != b.paged_pool_bytes) return true;
      if (a.nonpaged_pool_bytes != b.nonpaged_pool_bytes) return true;
      if (a.has_cpu != b.has_cpu_percent) return true;
      if (a.has_cpu && std::fabs(a.cpu_percent - b.cpu_percent) > 0.05)
        return true;
      if (a.has_disk != b.has_disk_bps) return true;
      if (a.has_disk && std::fabs(a.disk_bps - b.disk_bps) > 256.0) return true;
      if (a.has_net != b.has_net_bps) return true;
      if (a.has_net && std::fabs(a.net_bps - b.net_bps) > 256.0) return true;
      if (a.path != b.path) return true;
      if (a.has_is_critical != b.has_is_critical ||
          a.is_critical != b.is_critical)
        return true;
      return false;
    };

    std::unordered_set<uint32_t> live_pids;
    for (auto& [key, e] : current) {
      live_pids.insert(key.pid);
      if (full) {
        inv_out->upserts.push_back(std::move(e));
        continue;
      }
      const auto prev = prev_inventory_.find(key);
      if (prev == prev_inventory_.end() || changed(prev->second, e)) {
        inv_out->upserts.push_back(std::move(e));
      }
    }
    for (const auto& [key, _] : prev_inventory_) {
      if (current.find(key) == current.end() &&
          live_pids.find(key.pid) == live_pids.end()) {
        inv_out->removed_pids.push_back(key.pid);
      }
    }

    if (full) {
      last_full_resync_ms_ = now_ms;
      force_full_resync_ = false;
    }
  }

  prev_inventory_ = std::move(next_inv);
}

ipc::ProcessDetails HealthMetricsCollector::QueryProcessDetails(uint32_t pid) {
  std::lock_guard lock(mu_);
  ipc::ProcessDetails d;
  d.pid = pid;

  auto find_by_pid = [this](uint32_t target) -> const InvRowPrev* {
    for (const auto& [key, row] : prev_inventory_) {
      if (key.pid == target) return &row;
    }
    return nullptr;
  };

  if (const InvRowPrev* inv = find_by_pid(pid)) {
    d.name = inv->name;
    d.thread_count = inv->thread_count;
    d.handle_count = inv->handle_count;
    if (!inv->path.empty()) {
      d.path = inv->path;
      d.has_path = true;
    }
    if (inv->parent_pid != 0) {
      d.parent_pid = inv->parent_pid;
      d.has_parent_pid = true;
      if (const InvRowPrev* parent = find_by_pid(inv->parent_pid)) {
        if (!parent->name.empty()) {
          d.parent_name = parent->name;
          d.has_parent_name = true;
        }
      }
    }
  }

  std::string path = d.path;
  if (path.empty()) {
    path = ResolveProcessExecutablePath(pid, d.name);
    if (!path.empty()) {
      d.path = path;
      d.has_path = true;
    }
  }

  if (!path.empty()) {
    FillVersionStrings(path, &d);
  }

  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (h != nullptr) {
    // Prefer live parent from ProcessBasicInformation when available.
    auto NtQip = ResolveNtQip();
    if (NtQip != nullptr) {
      struct ProcessBasicInformation {
        PVOID Reserved1;
        PVOID PebBaseAddress;
        PVOID Reserved2[2];
        ULONG_PTR UniqueProcessId;
        ULONG_PTR InheritedFromUniqueProcessId;
      } pbi{};
      ULONG ret = 0;
      if (NtQip(h, 0 /*ProcessBasicInformation*/, &pbi, sizeof(pbi), &ret) >=
          0) {
        const uint32_t parent_pid =
            static_cast<uint32_t>(pbi.InheritedFromUniqueProcessId);
        if (parent_pid != 0) {
          d.parent_pid = parent_pid;
          d.has_parent_pid = true;
          if (const InvRowPrev* parent = find_by_pid(parent_pid)) {
            if (!parent->name.empty()) {
              d.parent_name = parent->name;
              d.has_parent_name = true;
            }
          }
        }
      }
    }

    FillTokenInfo(h, &d);
    FillArchitecture(h, &d);
    FillCommandLine(h, &d);
    FILETIME create{}, exit_t{}, kernel{}, user{};
    if (GetProcessTimes(h, &create, &exit_t, &kernel, &user)) {
      ULARGE_INTEGER u{};
      u.LowPart = create.dwLowDateTime;
      u.HighPart = create.dwHighDateTime;
      d.has_create_time = true;
      d.create_time_unix_ms =
          FileTimeToUnixMs(static_cast<int64_t>(u.QuadPart));
    }
    CloseHandle(h);
  }

  return d;
}

ipc::HealthSample HealthMetricsCollector::CollectSample() {
  return CollectHealthUpdate().sample;
}

ipc::HealthUpdate HealthMetricsCollector::CollectHealthUpdate() {
  std::lock_guard lock(mu_);
  ipc::HealthUpdate update;
  auto& sample = update.sample;
  sample.unix_ms = NowUnixMs();
  if (health_monitor_start_ms_ == 0) {
    health_monitor_start_ms_ = static_cast<uint64_t>(sample.unix_ms);
  }
  pdh_collected_this_sample_ = false;

  CollectPdhOnce();

  if (auto cpu = SampleCpuPercent()) {
    sample.has_cpu_percent = true;
    sample.cpu_percent = *cpu;
  }
  SampleMemory(&sample);
  SampleDiskSpace(&sample);
  SamplePhysicalDisks(&sample);
  SampleUptime(&sample);
  SampleNetwork(&sample);
  SampleDiskThroughput(&sample);
  SampleGpuPercent(&sample);
  SampleGpuExtended(gpu_adapter_, pdh_gpu_, pdh_gpu_ok_, pdh_query_,
                    &pdh_collected_this_sample_, nullptr, nullptr, &sample);
  SampleGpuAdapterMemory(&sample);
  SampleCpuFrequency(&sample);
  SampleCpuCores(&sample);
  SampleNetworkAddresses(&sample);
  SampleNetworkExtended(
      active_if_index_, active_adapter_, sample.net_download_bps,
      sample.net_upload_bps, sample.has_net_download_bps || sample.has_net_upload_bps,
      health_monitor_start_ms_, static_cast<uint64_t>(sample.unix_ms),
      &net_peak_download_bps_, &net_peak_upload_bps_, &net_sum_download_bps_,
      &net_sum_upload_bps_, &net_rate_samples_, &sample);
  SampleProcessesCombined(&sample, &update.process_inventory);
  SampleTopGpuFromPdh(&sample);
  return update;
}



std::string HealthMetricsCollector::ReadRegistryString(const wchar_t* subkey,
                                                       const wchar_t* value) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, subkey, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return {};
  }
  wchar_t buffer[512];
  DWORD type = 0;
  DWORD size = sizeof(buffer);
  const LONG rc = RegQueryValueExW(key, value, nullptr, &type,
                                   reinterpret_cast<LPBYTE>(buffer), &size);
  RegCloseKey(key);
  if (rc != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) {
    return {};
  }
  return TrimCopy(NarrowFromWide(buffer));
}

uint32_t HealthMetricsCollector::ReadRegistryDword(const wchar_t* subkey,
                                                   const wchar_t* value) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, subkey, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return 0;
  }
  DWORD data = 0;
  DWORD type = 0;
  DWORD size = sizeof(data);
  const LONG rc = RegQueryValueExW(key, value, nullptr, &type,
                                   reinterpret_cast<LPBYTE>(&data), &size);
  RegCloseKey(key);
  if (rc != ERROR_SUCCESS || type != REG_DWORD) return 0;
  return data;
}

void HealthMetricsCollector::QueryGpuInfo(std::string* model,
                                          uint64_t* dedicated_bytes,
                                          uint64_t* shared_bytes) {
  *model = {};
  *dedicated_bytes = 0;
  *shared_bytes = 0;
  IDXGIFactory1* factory = nullptr;
  if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1),
                                reinterpret_cast<void**>(&factory))) ||
      factory == nullptr) {
    return;
  }
  IDXGIAdapter1* adapter = nullptr;
  if (SUCCEEDED(factory->EnumAdapters1(0, &adapter)) && adapter != nullptr) {
    DXGI_ADAPTER_DESC1 desc{};
    if (SUCCEEDED(adapter->GetDesc1(&desc))) {
      *model = TrimCopy(NarrowFromWide(desc.Description));
      *dedicated_bytes = desc.DedicatedVideoMemory;
      *shared_bytes = desc.SharedSystemMemory;
    }
    adapter->Release();
  }
  factory->Release();
}

void HealthMetricsCollector::QueryCpuTopology(uint32_t* sockets,
                                              uint32_t* cores,
                                              uint32_t* logical) {
  *sockets = 0;
  *cores = 0;
  *logical = 0;
  DWORD len = 0;
  GetLogicalProcessorInformationEx(RelationAll, nullptr, &len);
  if (len == 0) {
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    *logical = si.dwNumberOfProcessors;
    *cores = *logical;
    *sockets = 1;
    return;
  }
  std::vector<uint8_t> buf(len);
  auto* info =
      reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(buf.data());
  if (!GetLogicalProcessorInformationEx(RelationAll, info, &len)) {
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    *logical = si.dwNumberOfProcessors;
    *cores = *logical;
    *sockets = 1;
    return;
  }
  BYTE* ptr = buf.data();
  BYTE* end = buf.data() + len;
  while (ptr < end) {
    auto* rec =
        reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(ptr);
    if (rec->Relationship == RelationProcessorCore) {
      ++(*cores);
      // Count set bits in GroupMask for logical processors on this core.
      for (WORD g = 0; g < rec->Processor.GroupCount; ++g) {
        KAFFINITY mask = rec->Processor.GroupMask[g].Mask;
        while (mask) {
          *logical += static_cast<uint32_t>(mask & 1);
          mask >>= 1;
        }
      }
    } else if (rec->Relationship == RelationProcessorPackage) {
      ++(*sockets);
    }
    ptr += rec->Size;
  }
  if (*sockets == 0) *sockets = 1;
  if (*logical == 0) {
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    *logical = si.dwNumberOfProcessors;
  }
  if (*cores == 0) *cores = *logical;
}

std::string HealthMetricsCollector::QueryActiveAdapterName() {
  PMIB_IF_TABLE2 table = nullptr;
  if (GetIfTable2(&table) != NO_ERROR || table == nullptr) return {};

  auto is_virtual = [](const MIB_IF_ROW2& row) -> bool {
    if (row.Type == IF_TYPE_SOFTWARE_LOOPBACK || row.Type == IF_TYPE_TUNNEL) {
      return true;
    }
    const wchar_t* desc = row.Description ? row.Description : L"";
    return wcsstr(desc, L"Virtual") || wcsstr(desc, L"Hyper-V") ||
           wcsstr(desc, L"vEthernet") || wcsstr(desc, L"VPN") ||
           wcsstr(desc, L"Teredo") || wcsstr(desc, L"ISATAP");
  };

  std::string best;
  uint64_t best_traffic = 0;
  std::string best_any;
  uint64_t best_any_traffic = 0;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const MIB_IF_ROW2& row = table->Table[i];
    if (row.OperStatus != IfOperStatusUp) continue;
    if (row.Type == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    const uint64_t traffic = row.InOctets + row.OutOctets;
    std::string name = NarrowFromWide(row.Description);
    if (name.empty()) name = NarrowFromWide(row.Alias);
    if (traffic >= best_any_traffic) {
      best_any_traffic = traffic;
      best_any = name;
    }
    if (is_virtual(row)) continue;
    if (traffic >= best_traffic) {
      best_traffic = traffic;
      best = name;
    }
  }
  FreeMibTable(table);
  return TrimCopy(best.empty() ? best_any : best);
}

uint64_t HealthMetricsCollector::QueryPrimaryStorageBytes() {
  ULARGE_INTEGER free_bytes{}, total_bytes{}, total_free{};
  if (!GetDiskFreeSpaceExW(L"C:\\", &free_bytes, &total_bytes, &total_free)) {
    return 0;
  }
  return total_bytes.QuadPart;
}

ipc::HealthStaticInfo HealthMetricsCollector::CollectStatic() {
  std::lock_guard lock(mu_);

  ipc::HealthStaticInfo info;
  info.windows_edition = ReadRegistryString(
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", L"ProductName");
  const std::string display = ReadRegistryString(
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", L"DisplayVersion");
  const std::string build = ReadRegistryString(
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", L"CurrentBuild");
  if (!display.empty() && !build.empty()) {
    info.windows_version = display + " (Build " + build + ")";
  } else if (!display.empty()) {
    info.windows_version = display;
  } else {
    info.windows_version = build;
  }

  info.cpu_model = ReadRegistryString(
      L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
      L"ProcessorNameString");
  info.cpu_base_mhz = cpu_base_mhz_ != 0
                          ? cpu_base_mhz_
                          : ReadRegistryDword(
                                L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                                L"~MHz");
  cpu_base_mhz_ = info.cpu_base_mhz;

  QueryCpuTopology(&info.cpu_sockets, &info.cpu_cores,
                   &info.cpu_logical_processors);
  cpu_logical_ = info.cpu_logical_processors;
  info.cpu_virtualization_enabled =
      IsProcessorFeaturePresent(PF_VIRT_FIRMWARE_ENABLED) != FALSE;
  EnrichCpuOverview(&info);

  gpu_adapter_ = QueryPrimaryGpuAdapter();
  EnrichGpuStaticInfo(gpu_adapter_, &info);
  if (info.gpu_model.empty()) {
    info.gpu_model = gpu_adapter_.model;
  }
  if (info.gpu_dedicated_bytes == 0) {
    info.gpu_dedicated_bytes = gpu_adapter_.dedicated_bytes;
  }
  if (info.gpu_shared_bytes == 0) {
    info.gpu_shared_bytes = gpu_adapter_.shared_bytes;
  }

  MEMORYSTATUSEX mem{};
  mem.dwLength = sizeof(mem);
  ULONGLONG installed_kb = 0;
  if (GetPhysicallyInstalledSystemMemory(&installed_kb) && installed_kb > 0) {
    info.installed_ram_bytes =
        static_cast<uint64_t>(installed_kb) * 1024ULL;
  } else if (GlobalMemoryStatusEx(&mem)) {
    info.installed_ram_bytes = mem.ullTotalPhys;
  }
  EnrichMemoryModules(&info);
  info.primary_storage_bytes = QueryPrimaryStorageBytes();
  EnrichPrimaryDiskIdentity(&info);
  info.active_network_adapter =
      active_adapter_.empty() ? QueryActiveAdapterName() : active_adapter_;
  if (active_adapter_.empty()) active_adapter_ = info.active_network_adapter;
  EnrichNetworkStatic(info.active_network_adapter, active_if_index_, &info);
  return info;
}

}  // namespace pulse
