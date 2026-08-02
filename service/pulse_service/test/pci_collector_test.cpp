#include "inventory/pci_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::PciCollector::Collect(100);
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "PciCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::AccessDenied) {
    std::cout << "pci_collector_tests SKIP access_denied\n";
    return 0;
  }
  if (result.entries.empty() &&
      result.status == pulse::ipc::InventoryStatus::Available) {
    std::cerr << "expected at least one PCI device\n";
    return 2;
  }
  for (const auto& e : result.entries) {
    if (e.id.empty()) {
      std::cerr << "pci entry missing stable instance id\n";
      return 3;
    }
  }
  std::cout << "pci_collector_tests OK count=" << result.entries.size()
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
