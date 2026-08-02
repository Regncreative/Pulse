#include "inventory/audio_collector.hpp"

#include "inventory/setupapi_device_enumerator.hpp"

namespace pulse::inventory {
namespace {

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

AudioCollector::Result AudioCollector::Collect(std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  GUID media_guid{};
  if (!ResolveSetupClassGuid(L"Media", &media_guid)) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "SetupDiClassGuidsFromNameW(Media) failed";
    return out;
  }

  const auto enumerated = EnumeratePresentByClassGuid(media_guid, cap);
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
  out.entries.reserve(enumerated.rows.size());
  for (const auto& row : enumerated.rows) {
    out.entries.push_back(FromRow(row));
  }

  if (out.truncated || enumerated.used_cfgmgr_fallback) {
    out.status = ipc::InventoryStatus::Partial;
    if (out.truncated && enumerated.used_cfgmgr_fallback) {
      out.status_detail =
          "Audio list truncated; some ids resolved via CM_Get_Device_IDW";
    } else if (out.truncated) {
      out.status_detail = "Audio list truncated at collector limit";
    } else {
      out.status_detail =
          "Some audio instance ids resolved via CM_Get_Device_IDW fallback";
    }
  } else {
    out.status = ipc::InventoryStatus::Available;
    out.status_detail = "Present Media class devices via SetupAPI";
  }
  return out;
}

}  // namespace pulse::inventory
