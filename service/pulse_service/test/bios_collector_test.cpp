#include "inventory/bios_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::BiosCollector::Collect();
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "BiosCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::Unsupported) {
    std::cout << "bios_collector_tests OK unsupported (no SMBIOS Type 0)\n";
    return 0;
  }
  if (result.entries.size() != 1) {
    std::cerr << "bios entries expected exactly 1, got " << result.entries.size()
              << "\n";
    return 2;
  }
  if (result.entries[0].id != "bios") {
    std::cerr << "bios entry missing stable id\n";
    return 3;
  }
  std::cout << "bios_collector_tests OK vendor=" << result.entries[0].vendor
            << " version=" << result.entries[0].version << "\n";
  return 0;
}
