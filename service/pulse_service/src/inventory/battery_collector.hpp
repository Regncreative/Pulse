#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Battery — SetupAPI Battery class + IOCTL_BATTERY_QUERY_*; fallback
/// GetSystemPowerStatus aggregate (id system_power, status partial).
class BatteryCollector {
 public:
  static constexpr std::uint32_t kDefaultLimit = 64;
  static constexpr std::uint32_t kCacheTtlMs = 30'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryBatteryEntry> entries;
  };

  [[nodiscard]] static Result Collect(std::uint32_t limit = kDefaultLimit);
};

}  // namespace pulse::inventory
