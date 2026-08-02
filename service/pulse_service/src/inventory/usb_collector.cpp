#include "inventory/usb_collector.hpp"

#include "inventory/setupapi_device_enumerator.hpp"

namespace pulse::inventory {

UsbCollector::Result UsbCollector::Collect(std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  const auto enumerated = EnumeratePresentByEnumerator(L"USB", cap);
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
    ipc::InventoryUsbEntry entry;
    entry.id = row.instance_id;
    entry.description = row.description;
    entry.hardware_id = row.hardware_id;
    entry.manufacturer = row.manufacturer;
    entry.service = row.service;
    entry.class_name = row.class_name;
    entry.class_guid = row.class_guid;
    entry.problem_code = row.problem_code;
    entry.has_problem_code = row.has_problem_code;
    out.entries.push_back(std::move(entry));
  }

  if (out.truncated || enumerated.used_cfgmgr_fallback) {
    out.status = ipc::InventoryStatus::Partial;
    if (out.truncated && enumerated.used_cfgmgr_fallback) {
      out.status_detail =
          "USB list truncated; some ids resolved via CM_Get_Device_IDW";
    } else if (out.truncated) {
      out.status_detail = "USB list truncated at collector limit";
    } else {
      out.status_detail =
          "Some USB instance ids resolved via CM_Get_Device_IDW fallback";
    }
  } else {
    out.status = ipc::InventoryStatus::Available;
    out.status_detail = "Present USB enumerator devices via SetupAPI";
  }
  return out;
}

}  // namespace pulse::inventory
