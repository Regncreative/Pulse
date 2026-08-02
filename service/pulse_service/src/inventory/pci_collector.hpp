#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// PCI domain — SetupAPI enumerator "PCI" (ADR-011). Membership only; GPU
/// PCIe link enrichment remains Health's display-adapter helper.
class PciCollector {
 public:
  static constexpr std::uint32_t kDefaultLimit = 4000;
  static constexpr std::uint32_t kCacheTtlMs = 60'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryPciEntry> entries;
  };

  [[nodiscard]] static Result Collect(std::uint32_t limit = kDefaultLimit);
};

}  // namespace pulse::inventory
