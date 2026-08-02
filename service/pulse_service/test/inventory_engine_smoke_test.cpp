#include "inventory/inventory_engine.hpp"

#include <chrono>
#include <iostream>

int main() {
  pulse::inventory::InventoryEngine engine;

  const pulse::ipc::InventoryDomainId domains[] = {
      pulse::ipc::InventoryDomainId::Services,
      pulse::ipc::InventoryDomainId::Drivers,
      pulse::ipc::InventoryDomainId::Software,
      pulse::ipc::InventoryDomainId::Usb,
      pulse::ipc::InventoryDomainId::Pci,
      pulse::ipc::InventoryDomainId::Displays,
      pulse::ipc::InventoryDomainId::Audio,
      pulse::ipc::InventoryDomainId::Bluetooth,
      pulse::ipc::InventoryDomainId::Printers,
      pulse::ipc::InventoryDomainId::Battery,
  };

  for (const auto domain : domains) {
    pulse::inventory::CollectRequest req;
    req.domain = domain;
    req.limit = 50;
    const auto t0 = std::chrono::steady_clock::now();
    const auto snap = engine.GetDomain(req);
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::steady_clock::now() - t0)
                        .count();
    if (snap.status == pulse::ipc::InventoryStatus::Error) {
      std::cerr << "domain " << static_cast<unsigned>(domain)
                << " error: " << snap.status_detail << "\n";
      return 1;
    }
    if (snap.status == pulse::ipc::InventoryStatus::AccessDenied) {
      std::cout << "domain " << static_cast<unsigned>(domain)
                << " SKIP access_denied\n";
      continue;
    }
    // Bluetooth/Battery may be unsupported on some machines — still valid.
    if (snap.status == pulse::ipc::InventoryStatus::Unsupported &&
        domain != pulse::ipc::InventoryDomainId::Bluetooth &&
        domain != pulse::ipc::InventoryDomainId::Battery &&
        domain != pulse::ipc::InventoryDomainId::Displays) {
      std::cerr << "domain " << static_cast<unsigned>(domain)
                << " unexpectedly unsupported\n";
      return 2;
    }
    if (snap.generation == 0 &&
        (snap.status == pulse::ipc::InventoryStatus::Available ||
         snap.status == pulse::ipc::InventoryStatus::Partial ||
         snap.status == pulse::ipc::InventoryStatus::Unsupported)) {
      std::cerr << "domain " << static_cast<unsigned>(domain)
                << " missing cache generation\n";
      return 4;
    }

    const size_t count = snap.services.size() + snap.drivers.size() +
                         snap.software.size() + snap.usb.size() +
                         snap.pci.size() + snap.displays.size() +
                         snap.audio.size() + snap.bluetooth.size() +
                         snap.printers.size() + snap.batteries.size();
    std::cout << "domain=" << static_cast<unsigned>(domain)
              << " status=" << static_cast<unsigned>(snap.status)
              << " count=" << count << " gen=" << snap.generation
              << " ms=" << ms << "\n";

    // Cache hit should be fast and keep generation.
    req.force_refresh = false;
    const auto t1 = std::chrono::steady_clock::now();
    const auto cached = engine.GetDomain(req);
    const auto cache_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - t1)
            .count();
    if (cached.generation != snap.generation) {
      std::cerr << "domain " << static_cast<unsigned>(domain)
                << " cache generation mismatch\n";
      return 5;
    }
    std::cout << "  cache_hit_ms=" << cache_ms << "\n";
  }

  std::cout << "inventory_engine_smoke_tests OK\n";
  return 0;
}
