#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Printers — EnumPrintersW read-only (ADR-011). Id = spooler printer name.
class PrintersCollector {
 public:
  static constexpr std::uint32_t kDefaultLimit = 512;
  static constexpr std::uint32_t kCacheTtlMs = 120'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryPrinterEntry> entries;
  };

  [[nodiscard]] static Result Collect(std::uint32_t limit = kDefaultLimit);
};

}  // namespace pulse::inventory
