#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Single Services-domain collector (ADR-011). Primary: EnumServicesStatusExW.
class ServicesCollector {
 public:
  static constexpr std::uint32_t kDefaultLimit = 2000;
  static constexpr std::uint32_t kCacheTtlMs = 30'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryServiceEntry> entries;
  };

  /// Enumerate Win32 services (installed + state). Observation only.
  [[nodiscard]] static Result Collect(std::uint32_t limit = kDefaultLimit);
};

}  // namespace pulse::inventory
