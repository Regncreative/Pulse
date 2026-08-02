#include "inventory/network_adapters_collector.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>

#include <cstdio>
#include <vector>

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "advapi32.lib")

namespace pulse::inventory {
namespace {

// --- Small string helpers (mirrors collectors/system_overview_info.cpp; not
// shared via a header today) ---

std::string NarrowFromWide(const wchar_t* wide) {
  if (wide == nullptr || wide[0] == L'\0') return {};
  const int needed =
      WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (needed <= 0) return {};
  std::string out(static_cast<size_t>(needed) - 1, '\0');
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

std::string OperStatusName(IF_OPER_STATUS status) {
  switch (status) {
    case IfOperStatusUp: return "Up";
    case IfOperStatusDown: return "Down";
    case IfOperStatusTesting: return "Testing";
    case IfOperStatusUnknown: return "Unknown";
    case IfOperStatusDormant: return "Dormant";
    case IfOperStatusNotPresent: return "NotPresent";
    case IfOperStatusLowerLayerDown: return "LowerLayerDown";
    default: return "";
  }
}

std::string SockAddrToString(const SOCKET_ADDRESS& addr) {
  if (addr.lpSockaddr == nullptr || addr.iSockaddrLength <= 0) return {};
  char host[INET6_ADDRSTRLEN]{};
  if (addr.lpSockaddr->sa_family == AF_INET) {
    const auto* sin = reinterpret_cast<const sockaddr_in*>(addr.lpSockaddr);
    if (InetNtopA(AF_INET, const_cast<IN_ADDR*>(&sin->sin_addr), host,
                 sizeof(host)) != nullptr) {
      return host;
    }
  } else if (addr.lpSockaddr->sa_family == AF_INET6) {
    const auto* sin6 = reinterpret_cast<const sockaddr_in6*>(addr.lpSockaddr);
    if (InetNtopA(AF_INET6, const_cast<IN6_ADDR*>(&sin6->sin6_addr), host,
                 sizeof(host)) != nullptr) {
      return host;
    }
  }
  return {};
}

/// Best-effort provider/version/date lookup via the Network Adapters driver
/// registry class key, matched by NetCfgInstanceId (the AdapterName reported
/// by GetAdaptersAddresses). Read-only; leaves fields unset on any failure.
/// Mirrors collectors/system_overview_info.cpp EnrichNetworkDriverInfo.
void EnrichDriverInfo(const std::string& net_cfg_instance_id,
                     ipc::InventoryNetworkAdapterEntry* entry) {
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
        entry->driver_provider = TrimCopy(NarrowFromWide(buf));
      }
      sz = sizeof(buf);
      type = 0;
      if (RegQueryValueExW(sub, L"DriverVersion", nullptr, &type,
                          reinterpret_cast<LPBYTE>(buf), &sz) ==
              ERROR_SUCCESS &&
          type == REG_SZ) {
        entry->driver_version = TrimCopy(NarrowFromWide(buf));
      }
      sz = sizeof(buf);
      type = 0;
      if (RegQueryValueExW(sub, L"DriverDate", nullptr, &type,
                          reinterpret_cast<LPBYTE>(buf), &sz) ==
              ERROR_SUCCESS &&
          type == REG_SZ) {
        entry->driver_date = TrimCopy(NarrowFromWide(buf));
      }
      RegCloseKey(sub);
      break;
    }
    RegCloseKey(sub);
  }

  RegCloseKey(class_key);
}

}  // namespace

NetworkAdaptersCollector::Result NetworkAdaptersCollector::Collect(
    std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  const ULONG flags = GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_INCLUDE_PREFIX;
  ULONG size = 0;
  ULONG first_rc = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, nullptr, &size);
  if (first_rc != ERROR_BUFFER_OVERFLOW || size == 0) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "GetAdaptersAddresses size query failed";
    return out;
  }

  std::vector<uint8_t> buf(size);
  auto* addrs = reinterpret_cast<IP_ADAPTER_ADDRESSES_LH*>(buf.data());
  const ULONG rc = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, addrs, &size);
  if (rc != NO_ERROR) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "GetAdaptersAddresses failed";
    return out;
  }

  for (auto* a = addrs; a != nullptr; a = a->Next) {
    if (out.entries.size() >= cap) {
      out.truncated = true;
      break;
    }

    const std::string adapter_name = a->AdapterName != nullptr ? a->AdapterName : "";
    if (adapter_name.empty()) continue;

    ipc::InventoryNetworkAdapterEntry entry;
    entry.id = adapter_name;
    entry.description = NarrowFromWide(a->Description);
    entry.friendly_name = NarrowFromWide(a->FriendlyName);
    entry.mac_address = MacAddressString(a->PhysicalAddress, a->PhysicalAddressLength);

    entry.connection_type = ConnectionTypeFromIfType(a->IfType);
    entry.is_loopback = a->IfType == IF_TYPE_SOFTWARE_LOOPBACK;
    if (entry.connection_type.empty() && entry.is_loopback) {
      entry.connection_type = "Loopback";
    }

    entry.if_index = a->IfIndex;
    entry.has_if_index = true;

    entry.mtu = a->Mtu;
    entry.has_mtu = true;

    entry.operational_status = OperStatusName(a->OperStatus);

    entry.dhcp_enabled = a->Dhcpv4Enabled != 0;
    entry.has_dhcp_enabled = true;

    constexpr uint64_t kUnknownLinkSpeed = 0xFFFFFFFFFFFFFFFFULL;
    if (a->TransmitLinkSpeed != 0 && a->TransmitLinkSpeed != kUnknownLinkSpeed) {
      entry.link_speed_bps = a->TransmitLinkSpeed;
      entry.has_link_speed_bps = true;
    }

    for (auto* ua = a->FirstUnicastAddress; ua != nullptr; ua = ua->Next) {
      const std::string ip = SockAddrToString(ua->Address);
      if (ip.empty()) continue;
      if (ua->Address.lpSockaddr->sa_family == AF_INET) {
        entry.ipv4_addresses.push_back(ip);
      } else if (ua->Address.lpSockaddr->sa_family == AF_INET6) {
        entry.ipv6_addresses.push_back(ip);
      }
    }

    for (auto* ga = a->FirstGatewayAddress; ga != nullptr; ga = ga->Next) {
      const std::string ip = SockAddrToString(ga->Address);
      if (!ip.empty()) entry.gateway_addresses.push_back(ip);
    }

    for (auto* da = a->FirstDnsServerAddress; da != nullptr; da = da->Next) {
      const std::string ip = SockAddrToString(da->Address);
      if (!ip.empty()) entry.dns_addresses.push_back(ip);
    }

    EnrichDriverInfo(adapter_name, &entry);

    out.entries.push_back(std::move(entry));
  }

  if (out.entries.empty()) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = "GetAdaptersAddresses returned no adapters";
    return out;
  }

  out.status = out.truncated ? ipc::InventoryStatus::Partial
                             : ipc::InventoryStatus::Available;
  out.status_detail = out.truncated
      ? "Network adapter list truncated at collector limit"
      : "GetAdaptersAddresses(AF_UNSPEC)";
  return out;
}

}  // namespace pulse::inventory
