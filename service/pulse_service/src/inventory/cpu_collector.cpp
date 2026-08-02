#include "inventory/cpu_collector.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <intrin.h>

#include <cstring>
#include <vector>

#pragma comment(lib, "advapi32.lib")

namespace pulse::inventory {
namespace {

// --- Small string helpers (mirrors system_overview_info.cpp /
// health_metrics_collector.cpp; not shared via a header today) ---

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
  while (!s.empty() &&
         (s.back() == ' ' || s.back() == '\t' || s.back() == '\0')) {
    s.pop_back();
  }
  size_t i = 0;
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t')) ++i;
  return s.substr(i);
}

std::string ReadRegistryString(const wchar_t* subkey, const wchar_t* value) {
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

std::uint32_t ReadRegistryDword(const wchar_t* subkey, const wchar_t* value) {
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

std::string CpuVendorFromCpuid() {
  int leaf0[4] = {0};
  __cpuid(leaf0, 0);
  char vendor[13] = {0};
  memcpy(vendor + 0, &leaf0[1], 4);
  memcpy(vendor + 4, &leaf0[3], 4);
  memcpy(vendor + 8, &leaf0[2], 4);
  vendor[12] = '\0';
  return std::string(vendor);
}

std::string CpuVirtualizationVendorFromCpuid() {
  int leaf1[4] = {0};
  __cpuid(leaf1, 1);
  const bool hypervisor_present = (leaf1[2] & (1 << 31)) != 0;
  if (!hypervisor_present) return {};

  int leaf0[4] = {0};
  __cpuid(leaf0, 0x40000000);
  char vendor[13] = {0};
  memcpy(vendor + 0, &leaf0[1], 4);
  memcpy(vendor + 4, &leaf0[2], 4);
  memcpy(vendor + 8, &leaf0[3], 4);
  vendor[12] = '\0';
  const std::string sig(vendor);

  if (sig == "Microsoft Hv") return "Microsoft Hyper-V";
  if (sig == "VMwareVMware") return "VMware";
  if (sig == "XenVMMXenVMM") return "Xen";
  if (sig == "VBoxVBoxVBox") return "Oracle VirtualBox";
  if (sig.rfind("KVMKVMKVM", 0) == 0) return "KVM";
  if (sig.rfind("prl hyperv", 0) == 0 || sig.rfind(" prl hyperv", 0) == 0) {
    return "Parallels";
  }
  if (sig.rfind("bhyve", 0) == 0) return "bhyve";
  return "Unknown hypervisor";
}

std::string CpuInstructionSet() {
  std::vector<std::string> features;
  if (IsProcessorFeaturePresent(PF_XMMI64_INSTRUCTIONS_AVAILABLE)) {
    features.push_back("SSE2");
  }
  if (IsProcessorFeaturePresent(PF_SSE3_INSTRUCTIONS_AVAILABLE)) {
    features.push_back("SSE3");
  }
  if (IsProcessorFeaturePresent(PF_SSE4_2_INSTRUCTIONS_AVAILABLE)) {
    features.push_back("SSE4.2");
  }
  if (IsProcessorFeaturePresent(PF_AVX_INSTRUCTIONS_AVAILABLE)) {
    features.push_back("AVX");
  }
  if (IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE)) {
    features.push_back("AVX2");
  }
  if (IsProcessorFeaturePresent(PF_AVX512F_INSTRUCTIONS_AVAILABLE)) {
    features.push_back("AVX512F");
  }
  std::string out;
  for (size_t i = 0; i < features.size(); ++i) {
    if (i > 0) out += ' ';
    out += features[i];
  }
  return out;
}

/// Topology + cache totals via GetLogicalProcessorInformationEx(RelationAll).
struct CpuTopology {
  std::uint32_t sockets = 0;
  std::uint32_t cores = 0;
  std::uint32_t logical = 0;
  std::uint32_t numa_nodes = 0;
  bool has_l1 = false;
  std::uint64_t l1_bytes = 0;
  bool has_l2 = false;
  std::uint64_t l2_bytes = 0;
  bool has_l3 = false;
  std::uint64_t l3_bytes = 0;
};

CpuTopology QueryCpuTopology() {
  CpuTopology topo;

  DWORD len = 0;
  GetLogicalProcessorInformationEx(RelationAll, nullptr, &len);
  if (len == 0) {
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    topo.logical = si.dwNumberOfProcessors;
    topo.cores = topo.logical;
    topo.sockets = 1;
    return topo;
  }

  std::vector<uint8_t> buf(len);
  auto* base =
      reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(buf.data());
  if (!GetLogicalProcessorInformationEx(RelationAll, base, &len)) {
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    topo.logical = si.dwNumberOfProcessors;
    topo.cores = topo.logical;
    topo.sockets = 1;
    return topo;
  }

  const uint8_t* ptr = buf.data();
  const uint8_t* end = buf.data() + len;
  while (ptr < end) {
    const auto* rec =
        reinterpret_cast<const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(ptr);
    if (rec->Relationship == RelationProcessorCore) {
      ++topo.cores;
      for (WORD g = 0; g < rec->Processor.GroupCount; ++g) {
        KAFFINITY mask = rec->Processor.GroupMask[g].Mask;
        while (mask) {
          topo.logical += static_cast<uint32_t>(mask & 1);
          mask >>= 1;
        }
      }
    } else if (rec->Relationship == RelationProcessorPackage) {
      ++topo.sockets;
    } else if (rec->Relationship == RelationNumaNode) {
      ++topo.numa_nodes;
    } else if (rec->Relationship == RelationCache) {
      const CACHE_RELATIONSHIP& cache = rec->Cache;
      if (cache.Level == 1) {
        topo.l1_bytes += cache.CacheSize;
        topo.has_l1 = true;
      } else if (cache.Level == 2) {
        topo.l2_bytes += cache.CacheSize;
        topo.has_l2 = true;
      } else if (cache.Level == 3) {
        topo.l3_bytes += cache.CacheSize;
        topo.has_l3 = true;
      }
    }
    if (rec->Size == 0) break;  // malformed; avoid infinite loop
    ptr += rec->Size;
  }

  if (topo.sockets == 0) topo.sockets = 1;
  if (topo.logical == 0) {
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    topo.logical = si.dwNumberOfProcessors;
  }
  if (topo.cores == 0) topo.cores = topo.logical;
  return topo;
}

}  // namespace

CpuCollector::Result CpuCollector::Collect() {
  Result out;

  ipc::InventoryCpuEntry entry;
  entry.id = "cpu";
  entry.name = ReadRegistryString(
      L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
      L"ProcessorNameString");
  entry.manufacturer = CpuVendorFromCpuid();

  SYSTEM_INFO si{};
  GetNativeSystemInfo(&si);
  switch (si.wProcessorArchitecture) {
    case PROCESSOR_ARCHITECTURE_AMD64:
      entry.architecture = "x64";
      break;
    case PROCESSOR_ARCHITECTURE_ARM64:
      entry.architecture = "ARM64";
      break;
    case PROCESSOR_ARCHITECTURE_INTEL:
      entry.architecture = "x86";
      break;
    default:
      break;
  }

  const CpuTopology topo = QueryCpuTopology();
  entry.sockets = topo.sockets;
  entry.has_sockets = topo.sockets > 0;
  entry.physical_cores = topo.cores;
  entry.has_physical_cores = topo.cores > 0;
  entry.logical_processors = topo.logical;
  entry.has_logical_processors = topo.logical > 0;
  entry.numa_nodes = topo.numa_nodes;
  entry.has_numa_nodes = topo.numa_nodes > 0;
  if (topo.has_l1) {
    entry.l1_cache_bytes = topo.l1_bytes;
    entry.has_l1_cache_bytes = true;
  }
  if (topo.has_l2) {
    entry.l2_cache_bytes = topo.l2_bytes;
    entry.has_l2_cache_bytes = true;
  }
  if (topo.has_l3) {
    entry.l3_cache_bytes = topo.l3_bytes;
    entry.has_l3_cache_bytes = true;
  }
  if (entry.has_logical_processors && entry.has_physical_cores) {
    entry.has_smt_enabled = true;
    entry.smt_enabled = entry.logical_processors > entry.physical_cores;
  }

  const std::uint32_t base_mhz = ReadRegistryDword(
      L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", L"~MHz");
  if (base_mhz > 0) {
    entry.base_clock_mhz = base_mhz;
    entry.has_base_clock_mhz = true;
  }

  entry.instruction_set = CpuInstructionSet();
  entry.virtualization_vendor = CpuVirtualizationVendorFromCpuid();

  out.entries.push_back(std::move(entry));

  if (out.entries[0].name.empty() && !out.entries[0].has_physical_cores) {
    out.status = ipc::InventoryStatus::Partial;
    out.status_detail =
        "CPU identity partially unavailable (registry/topology read failed)";
  } else {
    out.status = ipc::InventoryStatus::Available;
    out.status_detail =
        "Registry ProcessorNameString + GetLogicalProcessorInformationEx + CPUID";
  }
  return out;
}

}  // namespace pulse::inventory
