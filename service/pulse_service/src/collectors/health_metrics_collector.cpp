#include "collectors/health_metrics_collector.hpp"

#include "logging/logger.hpp"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstring>
#include <map>
#include <set>
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

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <dxgi.h>

#pragma comment(lib, "pdh.lib")
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "psapi.lib")

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
  initialized_ = true;
  Logger::Instance().Info("HealthMetrics",
                          "Collector initialized (Task Managerâ€“aligned counters)");
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
  pdh_cpu_perf_ = nullptr;
  pdh_cpu_utility_ = nullptr;
  pdh_cpu_cores_ = nullptr;
  pdh_mem_cache_ = nullptr;
  pdh_mem_modified_ = nullptr;
  pdh_mem_standby_reserve_ = nullptr;
  pdh_mem_standby_normal_ = nullptr;
  pdh_mem_standby_core_ = nullptr;
  pdh_disk_ok_ = false;
  pdh_disk_instances_ok_ = false;
  pdh_gpu_ok_ = false;
  pdh_cpu_perf_ok_ = false;
  pdh_cpu_utility_ok_ = false;
  pdh_cpu_cores_ok_ = false;
  pdh_mem_cache_ok_ = false;
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
  // Task Manager "In use" â‰ˆ Total âˆ’ Available (MS memory performance docs).
  out->memory_used_bytes = mem.ullTotalPhys - mem.ullAvailPhys;

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
  }

  SampleCachedMemoryFromPdh(out);
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

  std::map<uint32_t, double> by_pid;
  for (DWORD i = 0; i < item_count; ++i) {
    if (items[i].FmtValue.CStatus != ERROR_SUCCESS &&
        items[i].FmtValue.CStatus != PDH_CSTATUS_VALID_DATA) {
      continue;
    }
    const uint32_t pid = ParsePidFromGpuInstance(items[i].szName);
    if (pid == 0) continue;
    by_pid[pid] =
        (std::max)(by_pid[pid], items[i].FmtValue.doubleValue);
  }
  if (by_pid.empty()) return;

  std::vector<ipc::HealthProcessEntry> entries;
  for (const auto& [pid, util] : by_pid) {
    ipc::HealthProcessEntry e;
    e.pid = pid;
    e.has_gpu_percent = true;
    e.gpu_percent = util;
    e.path = ResolveProcessExecutablePath(pid, {});
    if (!e.path.empty()) {
      const auto slash = e.path.find_last_of("\\/");
      e.name = slash == std::string::npos ? e.path : e.path.substr(slash + 1);
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

void HealthMetricsCollector::SampleTopProcesses(ipc::HealthSample* out) {
  // Task Manager–style process inventory: NtQuerySystemInformation(
  // SystemProcessInformation). No OpenProcess, no PDH Process(*) counters.
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
  const double logical =
      static_cast<double>((std::max)(1u, cpu_logical_));

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
    // Grow slightly — process list can change between probes.
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

  std::unordered_map<uint32_t, ProcCpuPrev> next_cpu;
  std::unordered_map<uint32_t, ProcIoPrev> next_io;
  std::vector<ipc::HealthProcessEntry> cpu_rows;
  std::vector<ipc::HealthProcessEntry> mem_rows;
  std::vector<ipc::HealthProcessEntry> disk_rows;

  size_t offset = 0;
  for (;;) {
    if (offset + sizeof(PulseSystemProcessInformation) > buffer.size()) break;
    const auto* info = reinterpret_cast<const PulseSystemProcessInformation*>(
        buffer.data() + offset);

    const uint32_t pid = static_cast<uint32_t>(
        reinterpret_cast<uintptr_t>(info->UniqueProcessId));
    // Skip Idle (PID 0). Keep System (4) and everything else — Task Manager
    // Processes list excludes Idle from the interactive top consumers.
    if (pid != 0) {
      const std::string name = ProcessNameFromSpi(*info);
      const uint64_t cpu_100ns = static_cast<uint64_t>(info->KernelTime.QuadPart) +
                                static_cast<uint64_t>(info->UserTime.QuadPart);
      next_cpu[pid] = ProcCpuPrev{cpu_100ns};

      const uint64_t io_bytes =
          static_cast<uint64_t>(info->ReadTransferCount.QuadPart) +
          static_cast<uint64_t>(info->WriteTransferCount.QuadPart);
      next_io[pid] = ProcIoPrev{io_bytes};

      ipc::HealthProcessEntry base;
      base.pid = pid;
      base.name = name;
      base.thread_count = info->NumberOfThreads;
      base.handle_count = info->HandleCount;
      base.has_memory_bytes = true;
      base.memory_bytes = static_cast<uint64_t>(info->WorkingSetSize);

      if (have_proc_baseline_) {
        const auto it = prev_proc_cpu_.find(pid);
        if (it != prev_proc_cpu_.end() && cpu_100ns >= it->second.cpu_100ns) {
          const uint64_t delta = cpu_100ns - it->second.cpu_100ns;
          // 100ns units → seconds, then share of all logical processors.
          const double pct =
              (static_cast<double>(delta) / 10'000'000.0) / dt_s / logical *
              100.0;
          if (pct > 0.01) {
            ipc::HealthProcessEntry e = base;
            e.has_cpu_percent = true;
            e.cpu_percent = (std::min)(pct, 100.0);
            cpu_rows.push_back(std::move(e));
          }
        }

        const auto io_it = prev_proc_io_.find(pid);
        if (io_it != prev_proc_io_.end() && io_bytes >= io_it->second.bytes) {
          const double bps =
              static_cast<double>(io_bytes - io_it->second.bytes) / dt_s;
          if (bps > 1024.0) {
            ipc::HealthProcessEntry e = base;
            e.has_disk_bps = true;
            e.disk_bps = bps;
            disk_rows.push_back(std::move(e));
          }
        }
      }

      if (base.memory_bytes > 1024 * 1024) {
        mem_rows.push_back(std::move(base));
      }
    }

    if (info->NextEntryOffset == 0) break;
    offset += info->NextEntryOffset;
  }

  prev_proc_cpu_ = std::move(next_cpu);
  prev_proc_io_ = std::move(next_io);
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

  // Path fill only for retained tops (≤ 24 OpenProcess attempts). LocalService
  // often cannot open interactive user processes; known SystemRoot paths still
  // populate for common protected/system binaries.
  FillExecutablePaths(&cpu_rows);
  FillExecutablePaths(&mem_rows);
  FillExecutablePaths(&disk_rows);

  out->top_cpu = std::move(cpu_rows);
  out->top_memory = std::move(mem_rows);
  out->top_disk = std::move(disk_rows);
  out->top_network.clear();
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

  QueryGpuInfo(&info.gpu_model, &info.gpu_dedicated_bytes,
               &info.gpu_shared_bytes);

  MEMORYSTATUSEX mem{};
  mem.dwLength = sizeof(mem);
  if (GlobalMemoryStatusEx(&mem)) {
    info.installed_ram_bytes = mem.ullTotalPhys;
  }
  info.primary_storage_bytes = QueryPrimaryStorageBytes();
  info.active_network_adapter =
      active_adapter_.empty() ? QueryActiveAdapterName() : active_adapter_;
  return info;
}

ipc::HealthSample HealthMetricsCollector::CollectSample() {
  std::lock_guard lock(mu_);
  ipc::HealthSample sample;
  sample.unix_ms = NowUnixMs();
  pdh_collected_this_sample_ = false;

  // Temperatures: leave has_*_temp_c = false. Never fabricate.

  // Collect PDH once up front so Utility / GPU / Disk share one sample window.
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
  SampleCpuFrequency(&sample);
  SampleCpuCores(&sample);
  SampleNetworkAddresses(&sample);
  SampleTopProcesses(&sample);
  SampleTopGpuFromPdh(&sample);
  return sample;
}

}  // namespace pulse
