#include "inventory/memory_modules_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::MemoryModulesCollector::Collect(32);
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "MemoryModulesCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::Unsupported) {
    std::cout << "memory_modules_collector_tests OK unsupported (no SMBIOS Type 17)\n";
    return 0;
  }
  for (const auto& e : result.entries) {
    if (e.id.empty()) {
      std::cerr << "memory module entry missing stable id (Device Locator)\n";
      return 3;
    }
  }
  std::cout << "memory_modules_collector_tests OK count=" << result.entries.size()
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
