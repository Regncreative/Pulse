#include "inventory/inventory_engine.hpp"

#include <iostream>

int main() {
  pulse::inventory::InventoryEngine engine;

  const pulse::ipc::InventoryDomainId domains[] = {
      pulse::ipc::InventoryDomainId::Services,
      pulse::ipc::InventoryDomainId::Drivers,
      pulse::ipc::InventoryDomainId::Software,
      pulse::ipc::InventoryDomainId::Usb,
      pulse::ipc::InventoryDomainId::Pci,
  };

  for (const auto domain : domains) {
    pulse::inventory::CollectRequest req;
    req.domain = domain;
    req.limit = 50;
    const auto snap = engine.GetDomain(req);
    if (snap.status == pulse::ipc::InventoryStatus::Error) {
      std::cerr << "domain " << static_cast<unsigned>(domain)
                << " error: " << snap.status_detail << "\n";
      return 1;
    }
    if (snap.status == pulse::ipc::InventoryStatus::Unsupported) {
      std::cerr << "domain " << static_cast<unsigned>(domain)
                << " unexpectedly unsupported\n";
      return 2;
    }
    if (snap.status == pulse::ipc::InventoryStatus::AccessDenied) {
      std::cout << "domain " << static_cast<unsigned>(domain)
                << " SKIP access_denied\n";
      continue;
    }
    const size_t count = snap.services.size() + snap.drivers.size() +
                         snap.software.size() + snap.usb.size() +
                         snap.pci.size();
    if (count == 0 &&
        snap.status == pulse::ipc::InventoryStatus::Available) {
      std::cerr << "domain " << static_cast<unsigned>(domain)
                << " available but empty\n";
      return 3;
    }
    std::cout << "domain=" << static_cast<unsigned>(domain)
              << " status=" << static_cast<unsigned>(snap.status)
              << " count=" << count
              << " gen=" << snap.generation << "\n";
  }

  std::cout << "inventory_engine_smoke_tests OK\n";
  return 0;
}
