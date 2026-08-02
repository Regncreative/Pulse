#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// BIOS — SMBIOS Type 0 (BIOS Information) via shared RSMB helper
/// (smbios_table). Singleton domain; no fallback (ADR-011).
class BiosCollector {
 public:
  static constexpr std::uint32_t kCacheTtlMs = 300'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryBiosEntry> entries;
  };

  [[nodiscard]] static Result Collect();
};

}  // namespace pulse::inventory
