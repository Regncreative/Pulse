#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Storage — physical disk identity via SetupAPI GUID_DEVINTERFACE_DISK
/// enumeration + \\.\PhysicalDriveN + IOCTL_STORAGE_QUERY_PROPERTY.
/// Identity only; not live SMART telemetry (ADR-011).
class StorageCollector {
 public:
  static constexpr std::uint32_t kDefaultLimit = 64;
  static constexpr std::uint32_t kCacheTtlMs = 120'000;

  struct Result {
    ipc::InventoryStatus status = ipc::InventoryStatus::Error;
    std::string status_detail;
    bool truncated = false;
    std::vector<ipc::InventoryStorageEntry> entries;
  };

  [[nodiscard]] static Result Collect(std::uint32_t limit = kDefaultLimit);
};

}  // namespace pulse::inventory
