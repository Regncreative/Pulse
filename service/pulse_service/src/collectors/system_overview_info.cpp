#include "collectors/system_overview_info.hpp"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <intrin.h>
#include <winioctl.h>

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <netioapi.h>

#include <windot11.h>
#include <wlanapi.h>

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "wlanapi.lib")
#pragma comment(lib, "advapi32.lib")

namespace pulse {
namespace {

// --- Small string helpers (mirrors health_metrics_collector.cpp; not shared
// via a header today) ---

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

// --- CPU overview helpers ---

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

// --- SMBIOS (Type 17 Memory Device) parsing ---

uint8_t SmbiosReadU8(const uint8_t* base, uint8_t length, size_t offset) {
  if (offset + sizeof(uint8_t) > length) return 0;
  return base[offset];
}

uint16_t SmbiosReadU16(const uint8_t* base, uint8_t length, size_t offset) {
  if (offset + sizeof(uint16_t) > length) return 0;
  uint16_t v = 0;
  memcpy(&v, base + offset, sizeof(v));
  return v;
}

uint32_t SmbiosReadU32(const uint8_t* base, uint8_t length, size_t offset) {
  if (offset + sizeof(uint32_t) > length) return 0;
  uint32_t v = 0;
  memcpy(&v, base + offset, sizeof(v));
  return v;
}

bool SmbiosHasField(uint8_t length, size_t offset, size_t size) {
  return offset + size <= length;
}

/// Reads the (1-based) `index`th string from a structure's trailing string
/// table. Returns empty for index 0 (no string) or out-of-range access.
std::string SmbiosStringAt(const uint8_t* struct_start, uint8_t formatted_length,
                           const uint8_t* table_end, uint8_t index) {
  if (index == 0) return {};
  const uint8_t* p = struct_start + formatted_length;
  uint8_t current = 1;
  while (p < table_end && *p != 0) {
    const auto* s = reinterpret_cast<const char*>(p);
    const size_t max_len = static_cast<size_t>(table_end - p);
    const size_t len = strnlen(s, max_len);
    if (current == index) return std::string(s, len);
    p += len + 1;
    ++current;
  }
  return {};
}

/// Advances past a structure's formatted area and trailing (double-null
/// terminated) string set to the next structure header.
const uint8_t* SmbiosNextStructure(const uint8_t* struct_start,
                                   uint8_t formatted_length,
                                   const uint8_t* table_end) {
  const uint8_t* p = struct_start + formatted_length;
  while (p + 1 < table_end && !(p[0] == 0 && p[1] == 0)) ++p;
  return (p + 2 <= table_end) ? p + 2 : table_end;
}

std::string MemoryFormFactorName(uint8_t code) {
  switch (code) {
    case 0x01: return "Other";
    case 0x02: return "Unknown";
    case 0x03: return "SIMM";
    case 0x04: return "SIP";
    case 0x05: return "Chip";
    case 0x06: return "DIP";
    case 0x07: return "ZIP";
    case 0x08: return "Proprietary Card";
    case 0x09: return "DIMM";
    case 0x0A: return "TSOP";
    case 0x0B: return "Row of Chips";
    case 0x0C: return "RIMM";
    case 0x0D: return "SODIMM";
    case 0x0E: return "SRIMM";
    case 0x0F: return "FB-DIMM";
    case 0x10: return "Die";
    case 0x11: return "CAMM";
    default: return "";
  }
}

/// SMBIOS Type 17 "Memory Type" (Table 78). Values not listed are left
/// unset rather than guessed.
std::string MemoryTypeName(uint8_t code) {
  switch (code) {
    case 0x03: return "DRAM";
    case 0x0F: return "SDRAM";
    case 0x12: return "DDR";
    case 0x13: return "DDR2";
    case 0x14: return "DDR2 FB-DIMM";
    case 0x18: return "DDR3";
    case 0x1A: return "DDR4";
    case 0x1B: return "LPDDR";
    case 0x1C: return "LPDDR2";
    case 0x1D: return "LPDDR3";
    case 0x1E: return "LPDDR4";
    case 0x20: return "HBM";
    case 0x21: return "HBM2";
    case 0x22: return "DDR5";
    case 0x23: return "LPDDR5";
    case 0x24: return "HBM3";
    default: return "";
  }
}

// --- Disk identity helpers ---

std::string StorageBusTypeName(STORAGE_BUS_TYPE bus) {
  switch (bus) {
    case BusTypeScsi: return "SCSI";
    case BusTypeAtapi: return "ATAPI";
    case BusTypeAta: return "ATA";
    case BusType1394: return "IEEE1394";
    case BusTypeSsa: return "SSA";
    case BusTypeFibre: return "Fibre Channel";
    case BusTypeUsb: return "USB";
    case BusTypeRAID: return "RAID";
    case BusTypeiScsi: return "iSCSI";
    case BusTypeSas: return "SAS";
    case BusTypeSata: return "SATA";
    case BusTypeSd: return "SD";
    case BusTypeMmc: return "MMC";
    case BusTypeVirtual: return "Virtual";
    case BusTypeFileBackedVirtual: return "File-Backed Virtual";
    case BusTypeSpaces: return "Storage Spaces";
    case BusTypeNvme: return "NVMe";
    default: return "";
  }
}

// --- Network static helpers ---

std::string MacAddressString(const BYTE* address, ULONG length) {
  if (address == nullptr || length == 0) return {};
  std::string mac;
  mac.reserve(length * 3);
  char part[4];
  for (ULONG i = 0; i < length; ++i) {
    if (i > 0) mac += ':';
    sprintf_s(part, sizeof(part), "%02x", address[i]);
    mac += part;
  }
  return mac;
}

std::string ConnectionTypeFromIfType(IFTYPE if_type) {
  switch (if_type) {
    case IF_TYPE_ETHERNET_CSMACD: return "Ethernet";
    case IF_TYPE_IEEE80211: return "Wi-Fi";
    case IF_TYPE_PPP: return "PPP";
    case IF_TYPE_TUNNEL: return "Tunnel";
    case IF_TYPE_SOFTWARE_LOOPBACK: return "Loopback";
    case IF_TYPE_IEEE1394: return "FireWire";
    case IF_TYPE_ATM: return "ATM";
    default: return "";
  }
}

/// Best-effort provider/version/date lookup via the Network Adapters driver
/// registry class key, matched by NetCfgInstanceId (the adapter's GUID
/// name reported by GetAdaptersAddresses). Read-only; leaves fields unset
/// on any failure.
void EnrichNetworkDriverInfo(const std::string& net_cfg_instance_id,
                             ipc::HealthStaticInfo* info) {
  if (net_cfg_instance_id.empty()) return;

  static constexpr wchar_t kNetClassKey[] =
      L"SYSTEM\\CurrentControlSet\\Control\\Class\\"
      L"{4D36E972-E325-11CE-BFC1-08002BE10318}";

  HKEY class_key = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, kNetClassKey, 0, KEY_READ,
                    &class_key) != ERROR_SUCCESS) {
    return;
  }

  std::wstring target(net_cfg_instance_id.size(), L'\0');
  for (size_t i = 0; i < net_cfg_instance_id.size(); ++i) {
    target[i] = static_cast<wchar_t>(
        static_cast<unsigned char>(net_cfg_instance_id[i]));
  }

  for (DWORD i = 0;; ++i) {
    wchar_t subkey_name[32];
    DWORD subkey_len = static_cast<DWORD>(std::size(subkey_name));
    const LONG enum_rc = RegEnumKeyExW(class_key, i, subkey_name, &subkey_len,
                                       nullptr, nullptr, nullptr, nullptr);
    if (enum_rc == ERROR_NO_MORE_ITEMS) break;
    if (enum_rc != ERROR_SUCCESS) break;

    HKEY sub = nullptr;
    if (RegOpenKeyExW(class_key, subkey_name, 0, KEY_READ, &sub) !=
        ERROR_SUCCESS) {
      continue;
    }

    wchar_t instance_id[64] = {};
    DWORD instance_size = sizeof(instance_id);
    DWORD type = 0;
    const bool matches =
        RegQueryValueExW(sub, L"NetCfgInstanceId", nullptr, &type,
                        reinterpret_cast<LPBYTE>(instance_id),
                        &instance_size) == ERROR_SUCCESS &&
        type == REG_SZ && _wcsicmp(instance_id, target.c_str()) == 0;

    if (matches) {
      wchar_t buf[256] = {};
      DWORD sz = sizeof(buf);
      type = 0;
      if (RegQueryValueExW(sub, L"ProviderName", nullptr, &type,
                          reinterpret_cast<LPBYTE>(buf), &sz) ==
              ERROR_SUCCESS &&
          type == REG_SZ) {
        info->net_manufacturer = TrimCopy(NarrowFromWide(buf));
      }
      sz = sizeof(buf);
      type = 0;
      if (RegQueryValueExW(sub, L"DriverVersion", nullptr, &type,
                          reinterpret_cast<LPBYTE>(buf), &sz) ==
              ERROR_SUCCESS &&
          type == REG_SZ) {
        info->net_driver_version = TrimCopy(NarrowFromWide(buf));
      }
      sz = sizeof(buf);
      type = 0;
      if (RegQueryValueExW(sub, L"DriverDate", nullptr, &type,
                          reinterpret_cast<LPBYTE>(buf), &sz) ==
              ERROR_SUCCESS &&
          type == REG_SZ) {
        info->net_driver_date = TrimCopy(NarrowFromWide(buf));
      }
      RegCloseKey(sub);
      break;
    }
    RegCloseKey(sub);
  }

  RegCloseKey(class_key);
}

// --- WLAN (Wi-Fi) helpers ---

std::string WifiAuthAlgorithmName(DOT11_AUTH_ALGORITHM algo) {
  switch (algo) {
    case DOT11_AUTH_ALGO_80211_OPEN: return "Open";
    case DOT11_AUTH_ALGO_80211_SHARED_KEY: return "Shared Key";
    case DOT11_AUTH_ALGO_WPA: return "WPA-Enterprise";
    case DOT11_AUTH_ALGO_WPA_PSK: return "WPA-Personal";
    case DOT11_AUTH_ALGO_WPA_NONE: return "WPA-None";
    case DOT11_AUTH_ALGO_RSNA: return "WPA2-Enterprise";
    case DOT11_AUTH_ALGO_RSNA_PSK: return "WPA2-Personal";
    default:
      return "Auth(" + std::to_string(static_cast<uint32_t>(algo)) + ")";
  }
}

std::string WifiCipherAlgorithmName(DOT11_CIPHER_ALGORITHM algo) {
  switch (algo) {
    case DOT11_CIPHER_ALGO_NONE: return "";
    case DOT11_CIPHER_ALGO_WEP40: return "WEP40";
    case DOT11_CIPHER_ALGO_TKIP: return "TKIP";
    case DOT11_CIPHER_ALGO_CCMP: return "AES";
    case DOT11_CIPHER_ALGO_WEP104: return "WEP104";
    case DOT11_CIPHER_ALGO_WEP: return "WEP";
    default: return "";
  }
}

std::string WifiSecurityDescription(const WLAN_SECURITY_ATTRIBUTES& sec) {
  if (!sec.bSecurityEnabled) return "Open";
  const std::string auth = WifiAuthAlgorithmName(sec.dot11AuthAlgorithm);
  const std::string cipher = WifiCipherAlgorithmName(sec.dot11CipherAlgorithm);
  if (cipher.empty()) return auth;
  return auth + " (" + cipher + ")";
}

/// Current Wi-Fi connection (SSID / signal / channel / security) for the
/// active interface only. No-op (leaves fields empty) when WLAN AutoConfig
/// is unavailable or nothing is connected.
void SampleWifiInfo(ipc::HealthSample* out) {
  HANDLE client = nullptr;
  DWORD negotiated_version = 0;
  if (WlanOpenHandle(2, nullptr, &negotiated_version, &client) !=
          ERROR_SUCCESS ||
      client == nullptr) {
    return;
  }

  PWLAN_INTERFACE_INFO_LIST if_list = nullptr;
  if (WlanEnumInterfaces(client, nullptr, &if_list) != ERROR_SUCCESS ||
      if_list == nullptr) {
    WlanCloseHandle(client, nullptr);
    return;
  }

  for (DWORD i = 0; i < if_list->dwNumberOfItems; ++i) {
    const WLAN_INTERFACE_INFO& iface = if_list->InterfaceInfo[i];
    if (iface.isState != wlan_interface_state_connected) continue;

    DWORD data_size = 0;
    PWLAN_CONNECTION_ATTRIBUTES attrs = nullptr;
    WLAN_OPCODE_VALUE_TYPE opcode = wlan_opcode_value_type_invalid;
    if (WlanQueryInterface(client, &iface.InterfaceGuid,
                           wlan_intf_opcode_current_connection, nullptr,
                           &data_size, reinterpret_cast<PVOID*>(&attrs),
                           &opcode) == ERROR_SUCCESS &&
        attrs != nullptr) {
      const WLAN_ASSOCIATION_ATTRIBUTES& assoc =
          attrs->wlanAssociationAttributes;
      if (assoc.dot11Ssid.uSSIDLength > 0 &&
          assoc.dot11Ssid.uSSIDLength <= sizeof(assoc.dot11Ssid.ucSSID)) {
        out->net_ssid =
            std::string(reinterpret_cast<const char*>(assoc.dot11Ssid.ucSSID),
                       assoc.dot11Ssid.uSSIDLength);
      }
      out->has_net_signal_percent = true;
      out->net_signal_percent =
          static_cast<double>(assoc.wlanSignalQuality);
      out->net_wifi_security =
          WifiSecurityDescription(attrs->wlanSecurityAttributes);
      WlanFreeMemory(attrs);
    }

    DWORD channel_size = 0;
    PVOID channel_data = nullptr;
    WLAN_OPCODE_VALUE_TYPE channel_opcode = wlan_opcode_value_type_invalid;
    if (WlanQueryInterface(client, &iface.InterfaceGuid,
                           wlan_intf_opcode_channel_number, nullptr,
                           &channel_size, &channel_data,
                           &channel_opcode) == ERROR_SUCCESS &&
        channel_data != nullptr && channel_size >= sizeof(DWORD)) {
      DWORD channel = 0;
      memcpy(&channel, channel_data, sizeof(channel));
      out->net_wifi_channel = std::to_string(channel);
      WlanFreeMemory(channel_data);
    }

    // Only the first connected interface is reported.
    break;
  }

  WlanFreeMemory(if_list);
  WlanCloseHandle(client, nullptr);
}

}  // namespace

void EnrichCpuOverview(ipc::HealthStaticInfo* info) {
  if (info == nullptr) return;

  SYSTEM_INFO si{};
  GetNativeSystemInfo(&si);
  switch (si.wProcessorArchitecture) {
    case PROCESSOR_ARCHITECTURE_AMD64:
      info->cpu_architecture = "x64";
      break;
    case PROCESSOR_ARCHITECTURE_ARM64:
      info->cpu_architecture = "ARM64";
      break;
    case PROCESSOR_ARCHITECTURE_INTEL:
      info->cpu_architecture = "x86";
      break;
    default:
      break;
  }

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
  std::string instruction_set;
  for (size_t i = 0; i < features.size(); ++i) {
    if (i > 0) instruction_set += ' ';
    instruction_set += features[i];
  }
  info->cpu_instruction_set = instruction_set;

  DWORD len = 0;
  GetLogicalProcessorInformationEx(RelationAll, nullptr, &len);
  if (len > 0) {
    std::vector<uint8_t> buf(len);
    auto* base =
        reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(buf.data());
    if (GetLogicalProcessorInformationEx(RelationAll, base, &len)) {
      const uint8_t* ptr = buf.data();
      const uint8_t* end = buf.data() + len;
      uint32_t numa_nodes = 0;
      uint64_t l1 = 0, l2 = 0, l3 = 0;
      bool has_l1 = false, has_l2 = false, has_l3 = false;
      while (ptr < end) {
        const auto* rec =
            reinterpret_cast<const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(
                ptr);
        if (rec->Relationship == RelationNumaNode) {
          ++numa_nodes;
        } else if (rec->Relationship == RelationCache) {
          const CACHE_RELATIONSHIP& cache = rec->Cache;
          if (cache.Level == 1) {
            l1 += cache.CacheSize;
            has_l1 = true;
          } else if (cache.Level == 2) {
            l2 += cache.CacheSize;
            has_l2 = true;
          } else if (cache.Level == 3) {
            l3 += cache.CacheSize;
            has_l3 = true;
          }
        }
        if (rec->Size == 0) break;  // malformed; avoid infinite loop
        ptr += rec->Size;
      }
      info->cpu_numa_nodes = numa_nodes;
      if (has_l1) {
        info->has_cpu_l1_cache = true;
        info->cpu_l1_cache_bytes = l1;
      }
      if (has_l2) {
        info->has_cpu_l2_cache = true;
        info->cpu_l2_cache_bytes = l2;
      }
      if (has_l3) {
        info->has_cpu_l3_cache = true;
        info->cpu_l3_cache_bytes = l3;
      }
    }
  }

  if (info->cpu_logical_processors > 0 && info->cpu_cores > 0) {
    info->has_cpu_smt = true;
    info->cpu_smt_enabled =
        info->cpu_logical_processors > info->cpu_cores;
  }

  const std::string vendor = CpuVirtualizationVendorFromCpuid();
  if (!vendor.empty()) {
    info->cpu_virtualization_vendor = vendor;
  }
}

void EnrichMemoryModules(ipc::HealthStaticInfo* info) {
  if (info == nullptr) return;

  const DWORD signature = 'RSMB';
  const DWORD needed = GetSystemFirmwareTable(signature, 0, nullptr, 0);
  if (needed == 0) return;

  std::vector<uint8_t> buffer(needed);
  if (GetSystemFirmwareTable(signature, 0, buffer.data(),
                             static_cast<DWORD>(buffer.size())) != needed) {
    return;
  }
  if (buffer.size() < 8) return;

  uint32_t table_length = 0;
  memcpy(&table_length, buffer.data() + 4, sizeof(table_length));

  const uint8_t* table = buffer.data() + 8;
  const uint8_t* buffer_end = buffer.data() + buffer.size();
  const uint8_t* table_end = table + table_length;
  if (table_end > buffer_end) table_end = buffer_end;
  if (table >= table_end) return;

  uint32_t total_slots = 0;
  uint32_t populated_slots = 0;
  bool have_representative = false;

  const uint8_t* p = table;
  while (p + 4 <= table_end) {
    const uint8_t type = p[0];
    const uint8_t length = p[1];
    if (length < 4) break;  // malformed structure

    if (type == 127) break;  // End-of-Table marker

    if (type == 17) {
      ++total_slots;
      const uint16_t size_word = SmbiosReadU16(p, length, 0x0C);
      const bool populated = (size_word != 0 && size_word != 0xFFFF);
      if (populated) {
        ++populated_slots;
        if (!have_representative) {
          have_representative = true;

          const uint16_t total_width = SmbiosReadU16(p, length, 0x08);
          const uint16_t data_width = SmbiosReadU16(p, length, 0x0A);
          const uint8_t form_factor_code = SmbiosReadU8(p, length, 0x0E);
          const uint8_t memory_type_code = SmbiosReadU8(p, length, 0x12);
          const uint16_t speed =
              SmbiosHasField(length, 0x15, 2) ? SmbiosReadU16(p, length, 0x15)
                                              : 0;
          const uint8_t manufacturer_idx =
              SmbiosHasField(length, 0x17, 1) ? SmbiosReadU8(p, length, 0x17)
                                              : 0;
          const uint8_t serial_idx =
              SmbiosHasField(length, 0x18, 1) ? SmbiosReadU8(p, length, 0x18)
                                              : 0;
          const uint8_t part_idx =
              SmbiosHasField(length, 0x1A, 1) ? SmbiosReadU8(p, length, 0x1A)
                                              : 0;
          const uint32_t extended_speed =
              SmbiosHasField(length, 0x54, 4) ? SmbiosReadU32(p, length, 0x54)
                                              : 0;

          if (speed != 0 && speed != 0xFFFF) {
            info->has_mem_speed_mhz = true;
            info->mem_speed_mhz = speed;
          } else if (extended_speed != 0) {
            info->has_mem_speed_mhz = true;
            info->mem_speed_mhz = extended_speed;
          }

          const std::string form_factor =
              MemoryFormFactorName(form_factor_code);
          if (!form_factor.empty()) info->mem_form_factor = form_factor;

          const std::string ddr_gen = MemoryTypeName(memory_type_code);
          if (!ddr_gen.empty()) info->mem_ddr_generation = ddr_gen;

          // SMBIOS Type 17 has no dedicated ECC bit; ECC is reliably
          // indicated by Total Width exceeding Data Width (extra check
          // bits), per the DMTF SMBIOS spec.
          if (total_width != 0 && total_width != 0xFFFF && data_width != 0 &&
              data_width != 0xFFFF) {
            info->has_mem_ecc = true;
            info->mem_ecc = total_width > data_width;
          }

          const std::string manufacturer =
              TrimCopy(SmbiosStringAt(p, length, table_end, manufacturer_idx));
          if (!manufacturer.empty()) info->mem_dimm_vendor = manufacturer;

          const std::string part_number =
              TrimCopy(SmbiosStringAt(p, length, table_end, part_idx));
          if (!part_number.empty()) info->mem_dimm_part_number = part_number;

          const std::string serial =
              TrimCopy(SmbiosStringAt(p, length, table_end, serial_idx));
          if (!serial.empty()) info->mem_dimm_serial = serial;
        }
      }
    }

    p = SmbiosNextStructure(p, length, table_end);
  }

  if (total_slots > 0) {
    info->has_mem_module_count = true;
    info->mem_module_count = total_slots;
    info->has_mem_slots_used = true;
    info->mem_slots_used = populated_slots;
  }
  // mem_channels intentionally left unset — not reliably derivable from
  // SMBIOS Type 17 alone.
}

void EnrichPrimaryDiskIdentity(ipc::HealthStaticInfo* info) {
  if (info == nullptr) return;

  HANDLE disk = CreateFileW(
      L"\\\\.\\PhysicalDrive0", GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
  if (disk == INVALID_HANDLE_VALUE) return;

  STORAGE_PROPERTY_QUERY device_query{};
  device_query.PropertyId = StorageDeviceProperty;
  device_query.QueryType = PropertyStandardQuery;

  std::vector<uint8_t> device_buf(4096);
  DWORD device_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, &device_query,
                      sizeof(device_query), device_buf.data(),
                      static_cast<DWORD>(device_buf.size()), &device_bytes,
                      nullptr) &&
      device_bytes >= sizeof(STORAGE_DEVICE_DESCRIPTOR)) {
    const auto* desc =
        reinterpret_cast<const STORAGE_DEVICE_DESCRIPTOR*>(device_buf.data());

    auto read_offset_string = [&](DWORD offset) -> std::string {
      if (offset == 0 || offset >= device_buf.size()) return {};
      const auto* s = reinterpret_cast<const char*>(device_buf.data() + offset);
      const size_t max_len = device_buf.size() - offset;
      return TrimCopy(std::string(s, strnlen(s, max_len)));
    };

    const std::string product = read_offset_string(desc->ProductIdOffset);
    const std::string revision = read_offset_string(desc->ProductRevisionOffset);
    const std::string serial = read_offset_string(desc->SerialNumberOffset);

    if (!product.empty()) info->disk_model = product;
    if (!serial.empty()) info->disk_serial = serial;
    if (!revision.empty()) info->disk_firmware = revision;

    const std::string bus_name = StorageBusTypeName(desc->BusType);
    if (!bus_name.empty()) {
      info->disk_interface = bus_name;
      info->disk_bus = bus_name;
    }
  }

  STORAGE_PROPERTY_QUERY seek_query{};
  seek_query.PropertyId = StorageDeviceSeekPenaltyProperty;
  seek_query.QueryType = PropertyStandardQuery;
  DEVICE_SEEK_PENALTY_DESCRIPTOR seek_desc{};
  DWORD seek_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, &seek_query,
                      sizeof(seek_query), &seek_desc, sizeof(seek_desc),
                      &seek_bytes, nullptr) &&
      seek_bytes >= sizeof(seek_desc)) {
    if (!seek_desc.IncursSeekPenalty) {
      // Non-rotating media (SSD/NVMe); a real rotation rate is not
      // otherwise exposed for rotating disks via this IOCTL, so only the
      // "0 = SSD" case is reported.
      info->has_disk_rotation_rate = true;
      info->disk_rotation_rate = 0;
    }
  }

  STORAGE_PROPERTY_QUERY trim_query{};
  trim_query.PropertyId = StorageDeviceTrimProperty;
  trim_query.QueryType = PropertyStandardQuery;
  DEVICE_TRIM_DESCRIPTOR trim_desc{};
  DWORD trim_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, &trim_query,
                      sizeof(trim_query), &trim_desc, sizeof(trim_desc),
                      &trim_bytes, nullptr) &&
      trim_bytes >= sizeof(trim_desc)) {
    info->has_disk_trim = true;
    info->disk_trim_supported = trim_desc.TrimEnabled != FALSE;
  }

  DISK_GEOMETRY_EX geometry{};
  DWORD geometry_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_DISK_GET_DRIVE_GEOMETRY_EX, nullptr, 0,
                      &geometry, sizeof(geometry), &geometry_bytes, nullptr) &&
      geometry_bytes >= sizeof(DISK_GEOMETRY)) {
    info->has_disk_sector_size = true;
    info->disk_sector_size = geometry.Geometry.BytesPerSector;
  }

  std::vector<uint8_t> layout_buf(4096);
  DWORD layout_bytes = 0;
  if (DeviceIoControl(disk, IOCTL_DISK_GET_DRIVE_LAYOUT_EX, nullptr, 0,
                      layout_buf.data(), static_cast<DWORD>(layout_buf.size()),
                      &layout_bytes, nullptr) &&
      layout_bytes >= sizeof(DRIVE_LAYOUT_INFORMATION_EX)) {
    const auto* layout =
        reinterpret_cast<const DRIVE_LAYOUT_INFORMATION_EX*>(
            layout_buf.data());
    switch (layout->PartitionStyle) {
      case PARTITION_STYLE_GPT:
        info->disk_partition_style = "GPT";
        break;
      case PARTITION_STYLE_MBR:
        info->disk_partition_style = "MBR";
        break;
      case PARTITION_STYLE_RAW:
        info->disk_partition_style = "RAW";
        break;
      default:
        break;
    }
  }

  CloseHandle(disk);
}

void EnrichNetworkStatic(const std::string& active_adapter_name,
                         uint32_t active_if_index,
                         ipc::HealthStaticInfo* info) {
  if (info == nullptr) return;

  const ULONG flags = GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_INCLUDE_PREFIX;
  ULONG size = 0;
  GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, nullptr, &size);
  if (size == 0) return;

  std::vector<uint8_t> buf(size);
  auto* addrs = reinterpret_cast<IP_ADAPTER_ADDRESSES_LH*>(buf.data());
  if (GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, addrs, &size) !=
      NO_ERROR) {
    return;
  }

  IP_ADAPTER_ADDRESSES_LH* match = nullptr;
  for (auto* a = addrs; a != nullptr; a = a->Next) {
    if (active_if_index != 0 && a->IfIndex == active_if_index) {
      match = a;
      break;
    }
    const std::string desc = NarrowFromWide(a->Description);
    const std::string friendly = NarrowFromWide(a->FriendlyName);
    if (!active_adapter_name.empty() &&
        (desc == active_adapter_name || friendly == active_adapter_name)) {
      match = a;
      break;
    }
  }
  if (match == nullptr) return;

  info->net_description = NarrowFromWide(match->Description);

  const std::string mac =
      MacAddressString(match->PhysicalAddress, match->PhysicalAddressLength);
  if (!mac.empty()) info->net_mac_address = mac;

  info->has_net_mtu = true;
  info->net_mtu = match->Mtu;

  info->has_net_if_index = true;
  info->net_if_index = match->IfIndex;

  constexpr uint64_t kUnknownLinkSpeed = 0xFFFFFFFFFFFFFFFFULL;
  if (match->TransmitLinkSpeed != 0 &&
      match->TransmitLinkSpeed != kUnknownLinkSpeed) {
    info->has_net_link_speed_bps = true;
    info->net_link_speed_bps = match->TransmitLinkSpeed;
  }

  info->has_net_dhcp = true;
  info->net_dhcp_enabled = match->Dhcpv4Enabled != 0;

  if (match->Dhcpv4Server.lpSockaddr != nullptr &&
      match->Dhcpv4Server.iSockaddrLength > 0 &&
      match->Dhcpv4Server.lpSockaddr->sa_family == AF_INET) {
    const auto* sin =
        reinterpret_cast<sockaddr_in*>(match->Dhcpv4Server.lpSockaddr);
    char host[INET_ADDRSTRLEN]{};
    if (InetNtopA(AF_INET, &sin->sin_addr, host, sizeof(host)) != nullptr) {
      info->net_dhcp_server = host;
    }
  }

  // GetAdaptersAddresses does not expose DHCP lease timestamps; the legacy
  // (still supported) GetAdaptersInfo does, keyed by the same IfIndex.
  ULONG legacy_size = 0;
  GetAdaptersInfo(nullptr, &legacy_size);
  if (legacy_size > 0) {
    std::vector<uint8_t> legacy_buf(legacy_size);
    auto* legacy = reinterpret_cast<IP_ADAPTER_INFO*>(legacy_buf.data());
    if (GetAdaptersInfo(legacy, &legacy_size) == NO_ERROR) {
      for (auto* ai = legacy; ai != nullptr; ai = ai->Next) {
        if (ai->Index != match->IfIndex) continue;
        if (ai->LeaseObtained > 0) {
          info->has_net_lease_obtained = true;
          info->net_lease_obtained_unix_ms =
              static_cast<int64_t>(ai->LeaseObtained) * 1000;
        }
        if (ai->LeaseExpires > 0) {
          info->has_net_lease_expires = true;
          info->net_lease_expires_unix_ms =
              static_cast<int64_t>(ai->LeaseExpires) * 1000;
        }
        break;
      }
    }
  }

  const std::string connection_type = ConnectionTypeFromIfType(match->IfType);
  if (!connection_type.empty()) info->net_connection_type = connection_type;

  if (match->AdapterName != nullptr) {
    EnrichNetworkDriverInfo(match->AdapterName, info);
  }

  // Duplex is not exposed by a documented Win32 API for arbitrary adapters;
  // left empty per spec.
}

void SampleNetworkExtended(uint32_t active_if_index,
                           const std::string& active_adapter_name,
                           double download_bps, double upload_bps,
                           bool have_rates, uint64_t monitor_start_ms,
                           uint64_t now_ms, double* peak_down, double* peak_up,
                           double* sum_down, double* sum_up,
                           uint64_t* rate_samples, ipc::HealthSample* out) {
  (void)active_adapter_name;
  if (out == nullptr) return;

  uint64_t link_speed_bps = 0;

  if (active_if_index != 0) {
    MIB_IF_ROW2 row{};
    row.InterfaceIndex = active_if_index;
    if (GetIfEntry2(&row) == NO_ERROR) {
      out->has_net_bytes_sent = true;
      out->net_bytes_sent = row.OutOctets;
      out->has_net_bytes_received = true;
      out->net_bytes_received = row.InOctets;

      out->has_net_packets_sent = true;
      out->net_packets_sent = row.OutUcastPkts + row.OutNUcastPkts;
      out->has_net_packets_received = true;
      out->net_packets_received = row.InUcastPkts + row.InNUcastPkts;

      out->has_net_errors = true;
      out->net_errors = row.InErrors + row.OutErrors;

      out->has_net_drops = true;
      out->net_drops = row.InDiscards + row.OutDiscards;

      constexpr uint64_t kUnknownLinkSpeed = 0xFFFFFFFFFFFFFFFFULL;
      if (row.TransmitLinkSpeed != 0 &&
          row.TransmitLinkSpeed != kUnknownLinkSpeed) {
        link_speed_bps = row.TransmitLinkSpeed;
      }

      if (row.Type == IF_TYPE_IEEE80211) {
        SampleWifiInfo(out);
      }
    }
  }

  if (have_rates && peak_down != nullptr && peak_up != nullptr &&
      sum_down != nullptr && sum_up != nullptr && rate_samples != nullptr) {
    if (download_bps > *peak_down) *peak_down = download_bps;
    if (upload_bps > *peak_up) *peak_up = upload_bps;
    out->has_net_peak_download_bps = true;
    out->net_peak_download_bps = *peak_down;
    out->has_net_peak_upload_bps = true;
    out->net_peak_upload_bps = *peak_up;

    *sum_down += download_bps;
    *sum_up += upload_bps;
    ++(*rate_samples);
    if (*rate_samples > 0) {
      out->has_net_avg_download_bps = true;
      out->net_avg_download_bps =
          *sum_down / static_cast<double>(*rate_samples);
      out->has_net_avg_upload_bps = true;
      out->net_avg_upload_bps =
          *sum_up / static_cast<double>(*rate_samples);
    }

    if (link_speed_bps > 0) {
      const double utilization = (download_bps + upload_bps) * 8.0 /
                                 static_cast<double>(link_speed_bps) * 100.0;
      out->has_net_utilization_percent = true;
      out->net_utilization_percent =
          (std::min)(100.0, (std::max)(0.0, utilization));
    }
  }

  if (monitor_start_ms > 0 && now_ms >= monitor_start_ms) {
    out->has_net_connection_ms = true;
    out->net_connection_ms = now_ms - monitor_start_ms;
  }
}

}  // namespace pulse
