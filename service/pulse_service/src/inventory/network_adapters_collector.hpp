#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Network adapters — GetAdaptersAddresses primary; Network Adapters class
/// registry (matched by NetCfgInstanceId) enrichment for driver fields only
/// (not adapter membership/identity). Read-only (ADR-011).
class NetworkAdaptersCollector {
 public:
  static constexpr std::uint32_t kDefaultLimit = 64;
  static constexpr std::uint32_t kCacheTtlMs = 60'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryNetworkAdapterEntry> entries;
  };

  [[nodiscard]] static Result Collect(std::uint32_t limit = kDefaultLimit);
};

}  // namespace pulse::inventory
