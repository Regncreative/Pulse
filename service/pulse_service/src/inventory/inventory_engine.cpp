#include "inventory/inventory_engine.hpp"

#include "inventory/drivers_collector.hpp"
#include "inventory/services_collector.hpp"

#include <chrono>

namespace pulse::inventory {
namespace {

std::int64_t NowUnixMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(system_clock::now().time_since_epoch())
      .count();
}

bool CacheFresh(const DomainCacheMeta& meta, std::int64_t now_ms) {
  if (meta.generation == 0 || meta.cache_ttl_ms == 0) {
    return false;
  }
  return (now_ms - meta.generated_at_unix_ms) <
         static_cast<std::int64_t>(meta.cache_ttl_ms);
}

}  // namespace

ipc::InventoryDomainSnapshot InventoryEngine::MakeUnsupported(
    ipc::InventoryDomainId domain, std::uint32_t ttl_ms) const {
  ipc::InventoryDomainSnapshot snap;
  snap.domain = domain;
  snap.status = ipc::InventoryStatus::Unsupported;
  snap.status_detail = "Inventory domain collector not implemented yet";
  snap.full_resync = true;
  snap.cache_ttl_ms = ttl_ms;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectServices(
    std::uint32_t limit) {
  const auto collected = ServicesCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Services;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.services = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = ServicesCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectDrivers(
    std::uint32_t limit) {
  const auto collected = DriversCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Drivers;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.drivers = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = DriversCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectFresh(
    const CollectRequest& request) {
  switch (request.domain) {
    case ipc::InventoryDomainId::Services:
      return CollectServices(request.limit);
    case ipc::InventoryDomainId::Drivers:
      return CollectDrivers(request.limit);
    case ipc::InventoryDomainId::Software:
    case ipc::InventoryDomainId::Usb:
    case ipc::InventoryDomainId::Pci:
    case ipc::InventoryDomainId::Displays:
    case ipc::InventoryDomainId::Audio:
    case ipc::InventoryDomainId::Bluetooth:
    case ipc::InventoryDomainId::Printers:
    case ipc::InventoryDomainId::Battery:
    case ipc::InventoryDomainId::Motherboard:
    case ipc::InventoryDomainId::Bios:
    case ipc::InventoryDomainId::Cpu:
    case ipc::InventoryDomainId::MemoryModules:
    case ipc::InventoryDomainId::Storage:
    case ipc::InventoryDomainId::NetworkAdapters:
      return MakeUnsupported(request.domain, 60'000);
    case ipc::InventoryDomainId::Unspecified:
    default: {
      ipc::InventoryDomainSnapshot snap;
      snap.domain = request.domain;
      snap.status = ipc::InventoryStatus::Error;
      snap.status_detail = "Inventory domain unspecified";
      snap.full_resync = true;
      snap.generated_at_unix_ms = NowUnixMs();
      return snap;
    }
  }
}

ipc::InventoryDomainSnapshot InventoryEngine::ServeCachedOrCollect(
    CachedDomain* cache, const CollectRequest& request) {
  const std::int64_t now = NowUnixMs();
  const bool use_cache =
      !request.force_refresh && CacheFresh(cache->meta, now);
  if (use_cache) {
    auto snap = cache->snapshot;
    // Incremental diffs land in a follow-up; full snapshot for now.
    snap.full_resync = true;
    return snap;
  }

  auto snap = CollectFresh(request);
  if (snap.status == ipc::InventoryStatus::Available ||
      snap.status == ipc::InventoryStatus::Partial) {
    snap.generation = next_generation_++;
    cache->meta.generation = snap.generation;
    cache->meta.generated_at_unix_ms = snap.generated_at_unix_ms;
    cache->meta.cache_ttl_ms = snap.cache_ttl_ms;
    cache->snapshot = snap;
  } else {
    snap.generation = 0;
  }
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::GetDomain(
    const CollectRequest& request) {
  std::lock_guard lock(mutex_);

  if (request.domain == ipc::InventoryDomainId::Services) {
    return ServeCachedOrCollect(&services_, request);
  }
  if (request.domain == ipc::InventoryDomainId::Drivers) {
    return ServeCachedOrCollect(&drivers_, request);
  }

  // Unimplemented domains: no cache fill of unsupported beyond response.
  auto snap = CollectFresh(request);
  snap.generation = 0;
  return snap;
}

}  // namespace pulse::inventory
