#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Memory modules — SMBIOS Type 17 (Memory Device) list via shared RSMB
/// helper (smbios_table). Rows include unpopulated slots reported by
/// firmware; no fallback (ADR-011).
class MemoryModulesCollector {
 public:
  static constexpr std::uint32_t kDefaultLimit = 128;
  static constexpr std::uint32_t kCacheTtlMs = 300'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryMemoryModuleEntry> entries;
  };

  [[nodiscard]] static Result Collect(std::uint32_t limit = kDefaultLimit);
};

}  // namespace pulse::inventory
