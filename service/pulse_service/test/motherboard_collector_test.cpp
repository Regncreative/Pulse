#include "inventory/motherboard_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::MotherboardCollector::Collect();
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "MotherboardCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::Unsupported) {
    std::cout << "motherboard_collector_tests OK unsupported (no SMBIOS Type 2)\n";
    return 0;
  }
  if (result.entries.size() != 1) {
    std::cerr << "motherboard entries expected exactly 1, got "
              << result.entries.size() << "\n";
    return 2;
  }
  if (result.entries[0].id != "motherboard") {
    std::cerr << "motherboard entry missing stable id\n";
    return 3;
  }
  std::cout << "motherboard_collector_tests OK manufacturer="
            << result.entries[0].manufacturer
            << " product=" << result.entries[0].product << "\n";
  return 0;
}
