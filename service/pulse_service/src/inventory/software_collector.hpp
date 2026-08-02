#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Installed software — HKLM Uninstall registry only (ADR-011).
/// Gaps: HKCU per-user apps, Microsoft Store / UWP packages.
class SoftwareCollector {
 public:
  static constexpr std::uint32_t kDefaultLimit = 5000;
  static constexpr std::uint32_t kCacheTtlMs = 300'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventorySoftwareEntry> entries;
  };

  [[nodiscard]] static Result Collect(std::uint32_t limit = kDefaultLimit);
};

}  // namespace pulse::inventory
