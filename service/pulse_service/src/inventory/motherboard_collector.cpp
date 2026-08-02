#include "inventory/motherboard_collector.hpp"

#include "inventory/smbios_table.hpp"

namespace pulse::inventory {

MotherboardCollector::Result MotherboardCollector::Collect() {
  Result out;
  const auto table = ReadSmbiosTable();
  if (!table.available) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = table.status_detail;
    return out;
  }
  if (!table.has_motherboard) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = "SMBIOS Type 2 (Baseboard Information) not present";
    return out;
  }
  out.status = ipc::InventoryStatus::Available;
  out.status_detail = "SMBIOS Type 2 (Baseboard Information)";
  out.entries.push_back(table.motherboard);
  return out;
}

}  // namespace pulse::inventory
