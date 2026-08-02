#include "inventory/network_adapters_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::NetworkAdaptersCollector::Collect();
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "NetworkAdaptersCollector error: " << result.status_detail
              << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::Unsupported) {
    std::cout << "network_adapters_collector_tests SKIP (unsupported): "
              << result.status_detail << "\n";
    return 0;
  }
  if (result.entries.empty()) {
    std::cerr
        << "network adapter entries expected at least 1 (loopback) on a "
           "real machine\n";
    return 2;
  }
  bool found_loopback = false;
  for (const auto& adapter : result.entries) {
    if (adapter.id.empty()) {
      std::cerr << "network adapter entry missing stable id\n";
      return 3;
    }
    if (adapter.is_loopback) found_loopback = true;
  }
  if (!found_loopback) {
    std::cerr << "expected at least one loopback adapter to be reported\n";
    return 4;
  }
  std::cout << "network_adapters_collector_tests OK count="
            << result.entries.size()
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
