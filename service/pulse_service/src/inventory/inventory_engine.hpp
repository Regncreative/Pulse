#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <mutex>
#include <string>

namespace pulse::inventory {

/// Uniform cache contract (ADR-011 D3) — identical semantics for every domain.
struct DomainCacheMeta {
  std::uint64_t generation = 0;
  std::int64_t generated_at_unix_ms = 0;
  std::uint32_t cache_ttl_ms = 0;
};

struct CollectRequest {
  ipc::InventoryDomainId domain = ipc::InventoryDomainId::Unspecified;
  bool force_refresh = false;
  std::uint64_t since_generation = 0;
  std::uint32_t limit = 0;
};

/// Owns per-domain snapshots. Lazy; never runs on service start.
class InventoryEngine {
 public:
  InventoryEngine() = default;

  ipc::InventoryDomainSnapshot GetDomain(const CollectRequest& request);

 private:
  struct CachedDomain {
    DomainCacheMeta meta;
    ipc::InventoryDomainSnapshot snapshot;
  };

  ipc::InventoryDomainSnapshot CollectFresh(const CollectRequest& request);
  ipc::InventoryDomainSnapshot CollectServices(std::uint32_t limit);
  ipc::InventoryDomainSnapshot CollectDrivers(std::uint32_t limit);
  ipc::InventoryDomainSnapshot MakeUnsupported(
      ipc::InventoryDomainId domain, std::uint32_t ttl_ms) const;
  ipc::InventoryDomainSnapshot ServeCachedOrCollect(
      CachedDomain* cache, const CollectRequest& request);

  std::mutex mutex_;
  CachedDomain services_;
  CachedDomain drivers_;
  std::uint64_t next_generation_ = 1;
};

}  // namespace pulse::inventory
