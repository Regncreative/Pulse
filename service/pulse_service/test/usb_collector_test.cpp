#include "inventory/usb_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::UsbCollector::Collect(100);
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "UsbCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::AccessDenied) {
    std::cout << "usb_collector_tests SKIP access_denied\n";
    return 0;
  }
  // GitHub-hosted runners / VMs often expose no USB devices to SetupAPI.
  if (result.entries.empty()) {
    std::cout << "usb_collector_tests SKIP empty (no USB devices visible)\n";
    return 0;
  }
  for (const auto& e : result.entries) {
    if (e.id.empty()) {
      std::cerr << "usb entry missing stable instance id\n";
      return 3;
    }
  }
  std::cout << "usb_collector_tests OK count=" << result.entries.size()
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
