#include "inventory/displays_collector.hpp"

#include "inventory/setupapi_device_enumerator.hpp"
#include "windows/wevt_helpers.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <map>
#include <string>

namespace pulse::inventory {
namespace {

struct DisplayHint {
  std::string description;
  std::string adapter_name;
};

std::map<std::string, DisplayHint> BuildEnumDisplayHints() {
  std::map<std::string, DisplayHint> hints;
  DISPLAY_DEVICEW adapter{};
  adapter.cb = sizeof(adapter);
  for (DWORD a = 0; EnumDisplayDevicesW(nullptr, a, &adapter, 0); ++a) {
    if ((adapter.StateFlags & DISPLAY_DEVICE_ACTIVE) == 0) {
      continue;
    }
    const std::string adapter_name = wevt::WideToUtf8(adapter.DeviceString);
    DISPLAY_DEVICEW monitor{};
    monitor.cb = sizeof(monitor);
    for (DWORD m = 0; EnumDisplayDevicesW(adapter.DeviceName, m, &monitor, 0);
         ++m) {
      std::string id = wevt::WideToUtf8(monitor.DeviceID);
      if (id.empty()) {
        id = wevt::WideToUtf8(monitor.DeviceName);
      }
      if (id.empty()) {
        continue;
      }
      DisplayHint hint;
      hint.description = wevt::WideToUtf8(monitor.DeviceString);
      hint.adapter_name = adapter_name;
      hints[id] = std::move(hint);
    }
  }
  return hints;
}

ipc::InventoryPnPDeviceEntry FromRow(const SetupApiDeviceRow& row) {
  ipc::InventoryPnPDeviceEntry entry;
  entry.id = row.instance_id;
  entry.description = row.description;
  entry.hardware_id = row.hardware_id;
  entry.manufacturer = row.manufacturer;
  entry.service = row.service;
  entry.class_name = row.class_name;
  entry.class_guid = row.class_guid;
  entry.location_info = row.location_info;
  entry.problem_code = row.problem_code;
  entry.has_problem_code = row.has_problem_code;
  return entry;
}

}  // namespace

DisplaysCollector::Result DisplaysCollector::Collect(std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  GUID monitor_guid{};
  if (!ResolveSetupClassGuid(L"Monitor", &monitor_guid)) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "SetupDiClassGuidsFromNameW(Monitor) failed";
    return out;
  }

  const auto enumerated = EnumeratePresentByClassGuid(monitor_guid, cap);
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

  const auto hints = BuildEnumDisplayHints();
  bool used_enum_display = false;
  out.truncated = enumerated.truncated;
  out.entries.reserve(enumerated.rows.size());
  for (const auto& row : enumerated.rows) {
    auto entry = FromRow(row);
    const auto it = hints.find(entry.id);
    if (it != hints.end()) {
      entry.adapter_name = it->second.adapter_name;
      if (entry.description.empty() && !it->second.description.empty()) {
        entry.description = it->second.description;
        entry.description_from_enum_display = true;
        used_enum_display = true;
      }
    }
    out.entries.push_back(std::move(entry));
  }

  // When SetupAPI returns no monitors, surface active EnumDisplayDevices rows
  // as a partial inventory (ADR-011 description fallback path extended).
  if (out.entries.empty() && !hints.empty()) {
    for (const auto& [id, hint] : hints) {
      if (out.entries.size() >= cap) {
        out.truncated = true;
        break;
      }
      ipc::InventoryPnPDeviceEntry entry;
      entry.id = id;
      entry.description = hint.description;
      entry.adapter_name = hint.adapter_name;
      entry.description_from_enum_display = true;
      entry.class_name = "Monitor";
      out.entries.push_back(std::move(entry));
    }
    used_enum_display = true;
  }

  if (out.entries.empty()) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = "No present Monitor class devices";
    return out;
  }

  if (out.truncated || used_enum_display || enumerated.used_cfgmgr_fallback) {
    out.status = ipc::InventoryStatus::Partial;
    if (used_enum_display && out.truncated) {
      out.status_detail =
          "Display list truncated; some descriptions from EnumDisplayDevicesW";
    } else if (used_enum_display) {
      out.status_detail =
          "Some display descriptions/ids from EnumDisplayDevicesW fallback";
    } else if (out.truncated) {
      out.status_detail = "Display list truncated at collector limit";
    } else {
      out.status_detail =
          "Some display instance ids resolved via CM_Get_Device_IDW fallback";
    }
  } else {
    out.status = ipc::InventoryStatus::Available;
    out.status_detail = "Present Monitor class devices via SetupAPI";
  }
  return out;
}

}  // namespace pulse::inventory
