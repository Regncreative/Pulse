#include "inventory/software_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::SoftwareCollector::Collect(200);
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "SoftwareCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::AccessDenied) {
    std::cout << "software_collector_tests SKIP access_denied\n";
    return 0;
  }
  if (result.entries.empty() &&
      result.status == pulse::ipc::InventoryStatus::Available) {
    std::cerr << "expected at least one installed software entry\n";
    return 2;
  }
  for (const auto& e : result.entries) {
    if (e.id.empty() || e.display_name.empty()) {
      std::cerr << "software entry missing stable id or display name\n";
      return 3;
    }
  }
  std::cout << "software_collector_tests OK count=" << result.entries.size()
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
