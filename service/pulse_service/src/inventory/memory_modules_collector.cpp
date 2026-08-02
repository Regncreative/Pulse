#include "inventory/memory_modules_collector.hpp"

#include "inventory/smbios_table.hpp"

namespace pulse::inventory {

MemoryModulesCollector::Result MemoryModulesCollector::Collect(
    std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  const auto table = ReadSmbiosTable();
  if (!table.available) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = table.status_detail;
    return out;
  }
  if (table.memory_modules.empty()) {
    out.status = ipc::InventoryStatus::Unsupported;
    out.status_detail = "SMBIOS Type 17 (Memory Device) structures not present";
    return out;
  }

  if (table.memory_modules.size() > cap) {
    out.entries.assign(table.memory_modules.begin(),
                       table.memory_modules.begin() + cap);
    out.truncated = true;
    out.status = ipc::InventoryStatus::Partial;
    out.status_detail = "Memory module list truncated at collector limit";
  } else {
    out.entries = table.memory_modules;
    out.status = ipc::InventoryStatus::Available;
    out.status_detail = "SMBIOS Type 17 (Memory Device) list";
  }
  return out;
}

}  // namespace pulse::inventory
