#include "inventory/services_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::ServicesCollector::Collect(100);
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "ServicesCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::AccessDenied) {
    std::cout << "services_collector_tests SKIP access_denied\n";
    return 0;
  }
  if (result.entries.empty() &&
      result.status == pulse::ipc::InventoryStatus::Available) {
    std::cerr << "expected at least one Win32 service\n";
    return 2;
  }
  for (const auto& e : result.entries) {
    if (e.id.empty()) {
      std::cerr << "service entry missing stable id\n";
      return 3;
    }
  }
  std::cout << "services_collector_tests OK count=" << result.entries.size()
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
