#include "inventory/storage_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::StorageCollector::Collect();
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "StorageCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::AccessDenied) {
    std::cout << "storage_collector_tests SKIP (access_denied): "
              << result.status_detail << "\n";
    return 0;
  }
  if (result.status == pulse::ipc::InventoryStatus::Unsupported) {
    std::cout << "storage_collector_tests SKIP (unsupported): "
              << result.status_detail << "\n";
    return 0;
  }
  if (result.entries.empty()) {
    std::cerr << "storage entries expected at least 1 on a real machine\n";
    return 2;
  }
  for (const auto& disk : result.entries) {
    if (disk.id.empty()) {
      std::cerr << "storage entry missing stable id\n";
      return 3;
    }
  }
  const auto& disk0 = result.entries[0];
  std::cout << "storage_collector_tests OK count=" << result.entries.size()
            << " model=" << disk0.model << " bus=" << disk0.bus_type
            << " media=" << disk0.media_type
            << " size_bytes=" << disk0.size_bytes
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
