#include "inventory/bios_collector.hpp"

#include "inventory/smbios_table.hpp"

namespace pulse::inventory {

BiosCollector::Result BiosCollector::Collect() {
  Result out;
  const auto table = ReadSmbiosTable();
  if (!table.available) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = table.status_detail;
    return out;
  }
  if (!table.has_bios) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = "SMBIOS Type 0 (BIOS Information) not present";
    return out;
  }
  out.status = ipc::InventoryStatus::Available;
  out.status_detail = "SMBIOS Type 0 (BIOS Information)";
  out.entries.push_back(table.bios);
  return out;
}

}  // namespace pulse::inventory
