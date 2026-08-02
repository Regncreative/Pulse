#include "inventory/battery_collector.hpp"

#include "inventory/setupapi_device_enumerator.hpp"
#include "windows/wevt_helpers.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <SetupAPI.h>
#include <winioctl.h>
#include <batclass.h>

#include <cstring>
#include <string>
#include <vector>

#pragma comment(lib, "setupapi.lib")

namespace pulse::inventory {
namespace {

// GUID_DEVINTERFACE_BATTERY — defined without INITGUID to avoid poclass.h
// multiple-definition conflicts under MSVC.
// {72631e54-78a4-11d0-bcf7-00aa00b7b32a}
constexpr GUID kBatteryDeviceInterface = {
    0x72631e54,
    0x78a4,
    0x11d0,
    {0xbc, 0xf7, 0x00, 0xaa, 0x00, 0xb7, 0xb3, 0x2a}};

std::string PowerStateFromAcLine(BYTE ac_line) {
  if (ac_line == 1) return "online";
  if (ac_line == 0) return "offline";
  return "unknown";
}

bool QueryBatteryIoctl(const std::wstring& device_path,
                       ipc::InventoryBatteryEntry* entry) {
  const HANDLE handle = CreateFileW(
      device_path.c_str(), GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    return false;
  }

  ULONG tag = 0;
  DWORD bytes = 0;
  if (!DeviceIoControl(handle, IOCTL_BATTERY_QUERY_TAG, nullptr, 0, &tag,
                       sizeof(tag), &bytes, nullptr) ||
      tag == BATTERY_TAG_INVALID) {
    CloseHandle(handle);
    return false;
  }

  BATTERY_QUERY_INFORMATION query{};
  query.BatteryTag = tag;
  query.InformationLevel = BatteryInformation;
  BATTERY_INFORMATION info{};
  if (DeviceIoControl(handle, IOCTL_BATTERY_QUERY_INFORMATION, &query,
                      sizeof(query), &info, sizeof(info), &bytes, nullptr)) {
    if (info.Chemistry[0] != 0) {
      char chem[5]{};
      std::memcpy(chem, info.Chemistry, 4);
      entry->chemistry = chem;
    }
    if (info.DesignedCapacity != 0 &&
        info.DesignedCapacity != BATTERY_UNKNOWN_CAPACITY) {
      entry->design_capacity_mwh = info.DesignedCapacity;
      entry->has_design_capacity = true;
    }
    if (info.FullChargedCapacity != 0 &&
        info.FullChargedCapacity != BATTERY_UNKNOWN_CAPACITY) {
      entry->full_charged_capacity_mwh = info.FullChargedCapacity;
      entry->has_full_charged_capacity = true;
    }
    if (info.CycleCount != 0) {
      entry->cycle_count = info.CycleCount;
      entry->has_cycle_count = true;
    }
  }

  BATTERY_WAIT_STATUS wait{};
  wait.BatteryTag = tag;
  wait.Timeout = 0;
  wait.HighCapacity = BATTERY_UNKNOWN_CAPACITY;
  wait.LowCapacity = 0;
  BATTERY_STATUS status{};
  if (DeviceIoControl(handle, IOCTL_BATTERY_QUERY_STATUS, &wait, sizeof(wait),
                      &status, sizeof(status), &bytes, nullptr)) {
    if (status.Capacity != BATTERY_UNKNOWN_CAPACITY &&
        entry->has_full_charged_capacity &&
        entry->full_charged_capacity_mwh > 0) {
      entry->capacity_percent = static_cast<std::uint32_t>(
          (static_cast<std::uint64_t>(status.Capacity) * 100ULL) /
          entry->full_charged_capacity_mwh);
      if (entry->capacity_percent > 100) entry->capacity_percent = 100;
      entry->has_capacity_percent = true;
    }
    if ((status.PowerState & BATTERY_POWER_ON_LINE) != 0) {
      entry->power_state = "online";
    } else {
      entry->power_state = "offline";
    }
  }

  CloseHandle(handle);
  return entry->has_design_capacity || entry->has_full_charged_capacity ||
         entry->has_capacity_percent || !entry->chemistry.empty();
}

bool EnrichViaDeviceInterface(const std::string& instance_id_utf8,
                              ipc::InventoryBatteryEntry* entry) {
  GUID iface = kBatteryDeviceInterface;
  const HDEVINFO set = SetupDiGetClassDevsW(
      &iface, nullptr, nullptr, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  if (set == INVALID_HANDLE_VALUE) {
    return false;
  }

  bool enriched = false;
  SP_DEVICE_INTERFACE_DATA iface_data{};
  iface_data.cbSize = sizeof(iface_data);
  for (DWORD index = 0;
       SetupDiEnumDeviceInterfaces(set, nullptr, &iface, index, &iface_data);
       ++index) {
    DWORD needed = 0;
    SetupDiGetDeviceInterfaceDetailW(set, &iface_data, nullptr, 0, &needed,
                                     nullptr);
    if (needed == 0) {
      continue;
    }
    std::vector<BYTE> detail_buf(needed);
    auto* detail =
        reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(detail_buf.data());
    detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
    SP_DEVINFO_DATA info{};
    info.cbSize = sizeof(info);
    if (!SetupDiGetDeviceInterfaceDetailW(set, &iface_data, detail, needed,
                                          nullptr, &info)) {
      continue;
    }

    wchar_t id_buf[512]{};
    DWORD id_needed = 0;
    if (!SetupDiGetDeviceInstanceIdW(set, &info, id_buf, 512, &id_needed)) {
      continue;
    }
    if (wevt::WideToUtf8(id_buf) != instance_id_utf8) {
      continue;
    }

    enriched = QueryBatteryIoctl(detail->DevicePath, entry);
    break;
  }

  SetupDiDestroyDeviceInfoList(set);
  return enriched;
}

ipc::InventoryBatteryEntry SystemPowerFallbackEntry() {
  ipc::InventoryBatteryEntry entry;
  entry.id = "system_power";
  entry.description = "System power status aggregate";
  entry.from_system_power_fallback = true;

  SYSTEM_POWER_STATUS status{};
  if (!GetSystemPowerStatus(&status)) {
    entry.power_state = "unknown";
    return entry;
  }
  entry.power_state = PowerStateFromAcLine(status.ACLineStatus);
  if (status.BatteryLifePercent != 255) {
    entry.capacity_percent = status.BatteryLifePercent;
    entry.has_capacity_percent = true;
  }
  return entry;
}

bool SystemReportsNoBattery() {
  SYSTEM_POWER_STATUS status{};
  if (!GetSystemPowerStatus(&status)) {
    return false;
  }
  return (status.BatteryFlag & 128) != 0;
}

}  // namespace

BatteryCollector::Result BatteryCollector::Collect(std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  GUID battery_guid{};
  if (!ResolveSetupClassGuid(L"Battery", &battery_guid)) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "SetupDiClassGuidsFromNameW(Battery) failed";
    return out;
  }

  const auto enumerated = EnumeratePresentByClassGuid(battery_guid, cap);
  if (enumerated.access_denied) {
    out.status = ipc::InventoryStatus::AccessDenied;
    out.status_detail = enumerated.status_detail;
    return out;
  }
  if (enumerated.error) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = enumerated.status_detail;
    return out;
  }

  out.truncated = enumerated.truncated;
  bool any_ioctl = false;
  bool any_ioctl_attempt_failed = false;
  out.entries.reserve(enumerated.rows.size());
  for (const auto& row : enumerated.rows) {
    ipc::InventoryBatteryEntry entry;
    entry.id = row.instance_id;
    entry.description = row.description;
    entry.manufacturer = row.manufacturer;
    if (EnrichViaDeviceInterface(row.instance_id, &entry)) {
      any_ioctl = true;
    } else {
      any_ioctl_attempt_failed = true;
    }
    out.entries.push_back(std::move(entry));
  }

  if (out.entries.empty()) {
    if (SystemReportsNoBattery()) {
      out.status = ipc::InventoryStatus::Unsupported;
      out.status_detail = "No system battery";
      return out;
    }
    out.entries.push_back(SystemPowerFallbackEntry());
    out.status = ipc::InventoryStatus::Partial;
    out.status_detail =
        "No Battery class devices; using GetSystemPowerStatus aggregate";
    return out;
  }

  if (out.truncated || any_ioctl_attempt_failed || !any_ioctl ||
      enumerated.used_cfgmgr_fallback) {
    out.status = ipc::InventoryStatus::Partial;
    if (!any_ioctl) {
      out.status_detail =
          "Battery devices listed; IOCTL_BATTERY_QUERY_* unavailable";
    } else if (out.truncated) {
      out.status_detail = "Battery list truncated at collector limit";
    } else if (enumerated.used_cfgmgr_fallback) {
      out.status_detail =
          "Some battery instance ids resolved via CM_Get_Device_IDW fallback";
    } else {
      out.status_detail = "Battery inventory partial (mixed IOCTL enrichment)";
    }
  } else {
    out.status = ipc::InventoryStatus::Available;
    out.status_detail =
        "Present Battery class devices with IOCTL_BATTERY_QUERY_*";
  }
  return out;
}

}  // namespace pulse::inventory
