#include "inventory/bluetooth_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::BluetoothCollector::Collect(100);
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "BluetoothCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::AccessDenied) {
    std::cout << "bluetooth_collector_tests SKIP access_denied\n";
    return 0;
  }
  if (result.status == pulse::ipc::InventoryStatus::Unsupported) {
    std::cout << "bluetooth_collector_tests OK unsupported (no devices)\n";
    return 0;
  }
  for (const auto& e : result.entries) {
    if (e.id.empty()) {
      std::cerr << "bluetooth entry missing stable id\n";
      return 3;
    }
  }
  std::cout << "bluetooth_collector_tests OK count=" << result.entries.size()
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
