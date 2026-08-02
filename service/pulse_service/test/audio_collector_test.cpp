#include "inventory/audio_collector.hpp"

#include <iostream>

int main() {
  const auto result = pulse::inventory::AudioCollector::Collect(100);
  if (result.status == pulse::ipc::InventoryStatus::Error) {
    std::cerr << "AudioCollector error: " << result.status_detail << "\n";
    return 1;
  }
  if (result.status == pulse::ipc::InventoryStatus::AccessDenied) {
    std::cout << "audio_collector_tests SKIP access_denied\n";
    return 0;
  }
  for (const auto& e : result.entries) {
    if (e.id.empty()) {
      std::cerr << "audio entry missing stable id\n";
      return 3;
    }
  }
  std::cout << "audio_collector_tests OK count=" << result.entries.size()
            << " status=" << static_cast<unsigned>(result.status) << "\n";
  return 0;
}
