#include "inventory/cpu_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::CpuCollector::Collect();
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "CpuCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.entries.size() != 1) {
    std::cerr << "cpu entries expected exactly 1, got " << result.entries.size()
              << "\n";
    return 2;
  }
  const auto& cpu = result.entries[0];
  if (cpu.id != "cpu") {
    std::cerr << "cpu entry missing stable id\n";
    return 3;
  }
  if (!cpu.has_logical_processors || cpu.logical_processors == 0) {
    std::cerr << "cpu entry missing logical processor count\n";
    return 4;
  }
  std::cout << "cpu_collector_tests OK name=" << cpu.name
            << " manufacturer=" << cpu.manufacturer
            << " logical=" << cpu.logical_processors
            << " cores=" << cpu.physical_cores
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
