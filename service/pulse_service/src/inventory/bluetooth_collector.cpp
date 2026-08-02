#include "inventory/bluetooth_collector.hpp"

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

BluetoothCollector::Result BluetoothCollector::Collect(std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  GUID bluetooth_guid{};
  if (!ResolveSetupClassGuid(L"Bluetooth", &bluetooth_guid)) {
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "SetupDiClassGuidsFromNameW(Bluetooth) failed";
    return out;
  }

  const auto enumerated = EnumeratePresentByClassGuid(bluetooth_guid, cap);
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

  if (out.entries.empty()) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = "No present Bluetooth class devices";
    return out;
  }

  if (out.truncated || enumerated.used_cfgmgr_fallback) {
    out.status = ipc::InventoryStatus::Partial;
    if (out.truncated && enumerated.used_cfgmgr_fallback) {
      out.status_detail =
          "Bluetooth list truncated; some ids resolved via CM_Get_Device_IDW";
    } else if (out.truncated) {
      out.status_detail = "Bluetooth list truncated at collector limit";
    } else {
      out.status_detail =
          "Some Bluetooth instance ids resolved via CM_Get_Device_IDW fallback";
    }
  } else {
    out.status = ipc::InventoryStatus::Available;
    out.status_detail = "Present Bluetooth class devices via SetupAPI";
  }
  return out;
}

}  // namespace pulse::inventory
