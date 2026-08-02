#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Displays — SetupAPI Monitor class; EnumDisplayDevicesW description fallback.
class DisplaysCollector {
 public:
  static constexpr std::uint32_t kDefaultLimit = 256;
  static constexpr std::uint32_t kCacheTtlMs = 60'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryPnPDeviceEntry> entries;
  };

  [[nodiscard]] static Result Collect(std::uint32_t limit = kDefaultLimit);
};

}  // namespace pulse::inventory
