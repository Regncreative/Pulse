#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Motherboard — SMBIOS Type 2 (Baseboard Information) via shared RSMB
/// helper (smbios_table). Singleton domain; no fallback (ADR-011).
class MotherboardCollector {
 public:
  static constexpr std::uint32_t kCacheTtlMs = 300'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryMotherboardEntry> entries;
  };

  [[nodiscard]] static Result Collect();
};

}  // namespace pulse::inventory
