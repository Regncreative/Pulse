#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// CPU — registry ProcessorNameString + GetLogicalProcessorInformationEx +
/// CPUID identity (same patterns as collectors/system_overview_info.cpp
/// EnrichCpuOverview / health_metrics_collector.cpp CollectStatic). Singleton
/// domain; no fallback (ADR-011). Not shared with Health's own path.
class CpuCollector {
 public:
  static constexpr std::uint32_t kCacheTtlMs = 300'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryCpuEntry> entries;
  };

  [[nodiscard]] static Result Collect();
};

}  // namespace pulse::inventory
