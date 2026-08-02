#include "inventory/inventory_engine.hpp"

#include "inventory/audio_collector.hpp"
#include "inventory/battery_collector.hpp"
#include "inventory/bios_collector.hpp"
#include "inventory/bluetooth_collector.hpp"
#include "inventory/cpu_collector.hpp"
#include "inventory/displays_collector.hpp"
#include "inventory/drivers_collector.hpp"
#include "inventory/memory_modules_collector.hpp"
#include "inventory/motherboard_collector.hpp"
#include "inventory/network_adapters_collector.hpp"
#include "inventory/pci_collector.hpp"
#include "inventory/printers_collector.hpp"
#include "inventory/services_collector.hpp"
#include "inventory/software_collector.hpp"
#include "inventory/storage_collector.hpp"
#include "inventory/usb_collector.hpp"

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

ipc::InventoryDomainSnapshot InventoryEngine::CollectSoftware(
    std::uint32_t limit) {
  const auto collected = SoftwareCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Software;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.software = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = SoftwareCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectUsb(std::uint32_t limit) {
  const auto collected = UsbCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Usb;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.usb = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = UsbCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectPci(std::uint32_t limit) {
  const auto collected = PciCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Pci;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.pci = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = PciCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectDisplays(
    std::uint32_t limit) {
  const auto collected = DisplaysCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Displays;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.displays = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = DisplaysCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectAudio(std::uint32_t limit) {
  const auto collected = AudioCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Audio;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.audio = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = AudioCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectBluetooth(
    std::uint32_t limit) {
  const auto collected = BluetoothCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Bluetooth;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.bluetooth = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = BluetoothCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectPrinters(
    std::uint32_t limit) {
  const auto collected = PrintersCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Printers;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.printers = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = PrintersCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectBattery(
    std::uint32_t limit) {
  const auto collected = BatteryCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Battery;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.batteries = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = BatteryCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectMotherboard() {
  const auto collected = MotherboardCollector::Collect();
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Motherboard;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.motherboard = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = MotherboardCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectBios() {
  const auto collected = BiosCollector::Collect();
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Bios;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.bios = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = BiosCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectCpu() {
  const auto collected = CpuCollector::Collect();
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Cpu;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.cpu = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = CpuCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectMemoryModules(
    std::uint32_t limit) {
  const auto collected = MemoryModulesCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::MemoryModules;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.memory_modules = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = MemoryModulesCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectStorage(
    std::uint32_t limit) {
  const auto collected = StorageCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::Storage;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.storage = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = StorageCollector::kCacheTtlMs;
  snap.generated_at_unix_ms = NowUnixMs();
  return snap;
}

ipc::InventoryDomainSnapshot InventoryEngine::CollectNetworkAdapters(
    std::uint32_t limit) {
  const auto collected = NetworkAdaptersCollector::Collect(limit);
  ipc::InventoryDomainSnapshot snap;
  snap.domain = ipc::InventoryDomainId::NetworkAdapters;
  snap.status = collected.status;
  snap.status_detail = collected.status_detail;
  snap.truncated = collected.truncated;
  snap.network_adapters = collected.entries;
  snap.full_resync = true;
  snap.cache_ttl_ms = NetworkAdaptersCollector::kCacheTtlMs;
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
      return CollectSoftware(request.limit);
    case ipc::InventoryDomainId::Usb:
      return CollectUsb(request.limit);
    case ipc::InventoryDomainId::Pci:
      return CollectPci(request.limit);
    case ipc::InventoryDomainId::Displays:
      return CollectDisplays(request.limit);
    case ipc::InventoryDomainId::Audio:
      return CollectAudio(request.limit);
    case ipc::InventoryDomainId::Bluetooth:
      return CollectBluetooth(request.limit);
    case ipc::InventoryDomainId::Printers:
      return CollectPrinters(request.limit);
    case ipc::InventoryDomainId::Battery:
      return CollectBattery(request.limit);
    case ipc::InventoryDomainId::Motherboard:
      return CollectMotherboard();
    case ipc::InventoryDomainId::Bios:
      return CollectBios();
    case ipc::InventoryDomainId::Cpu:
      return CollectCpu();
    case ipc::InventoryDomainId::MemoryModules:
      return CollectMemoryModules(request.limit);
    case ipc::InventoryDomainId::Storage:
      return CollectStorage(request.limit);
    case ipc::InventoryDomainId::NetworkAdapters:
      return CollectNetworkAdapters(request.limit);
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

InventoryEngine::CachedDomain* InventoryEngine::CacheFor(
    ipc::InventoryDomainId domain) {
  switch (domain) {
    case ipc::InventoryDomainId::Services:
      return &services_;
    case ipc::InventoryDomainId::Drivers:
      return &drivers_;
    case ipc::InventoryDomainId::Software:
      return &software_;
    case ipc::InventoryDomainId::Usb:
      return &usb_;
    case ipc::InventoryDomainId::Pci:
      return &pci_;
    case ipc::InventoryDomainId::Displays:
      return &displays_;
    case ipc::InventoryDomainId::Audio:
      return &audio_;
    case ipc::InventoryDomainId::Bluetooth:
      return &bluetooth_;
    case ipc::InventoryDomainId::Printers:
      return &printers_;
    case ipc::InventoryDomainId::Battery:
      return &battery_;
    case ipc::InventoryDomainId::Motherboard:
      return &motherboard_;
    case ipc::InventoryDomainId::Bios:
      return &bios_;
    case ipc::InventoryDomainId::Cpu:
      return &cpu_;
    case ipc::InventoryDomainId::MemoryModules:
      return &memory_modules_;
    case ipc::InventoryDomainId::Storage:
      return &storage_;
    case ipc::InventoryDomainId::NetworkAdapters:
      return &network_adapters_;
    default:
      return nullptr;
  }
}

ipc::InventoryDomainSnapshot InventoryEngine::ServeCachedOrCollect(
    CachedDomain* cache, const CollectRequest& request) {
  const std::int64_t now = NowUnixMs();
  const bool use_cache =
      !request.force_refresh && CacheFresh(cache->meta, now);
  if (use_cache) {
    auto snap = cache->snapshot;
    snap.full_resync = true;
    return snap;
  }

  auto snap = CollectFresh(request);
  // Cache successful observation states, including unsupported empty catalogs
  // (e.g. no Bluetooth) so refresh/TTL semantics stay uniform.
  if (snap.status == ipc::InventoryStatus::Available ||
      snap.status == ipc::InventoryStatus::Partial ||
      snap.status == ipc::InventoryStatus::Unsupported) {
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

  if (CachedDomain* cache = CacheFor(request.domain)) {
    return ServeCachedOrCollect(cache, request);
  }

  auto snap = CollectFresh(request);
  snap.generation = 0;
  return snap;
}

}  // namespace pulse::inventory
