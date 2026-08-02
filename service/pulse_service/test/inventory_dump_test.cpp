// Dumps Inventory domain identity fields for native-tool spot-check (R3).
#include "inventory/inventory_engine.hpp"

#include <iostream>
#include <string>

namespace {

const char* StatusName(pulse::ipc::InventoryStatus s) {
  switch (s) {
    case pulse::ipc::InventoryStatus::Available: return "available";
    case pulse::ipc::InventoryStatus::Unsupported: return "unsupported";
    case pulse::ipc::InventoryStatus::AccessDenied: return "access_denied";
    case pulse::ipc::InventoryStatus::Partial: return "partial";
    case pulse::ipc::InventoryStatus::Error: return "error";
    default: return "unspecified";
  }
}

void DumpDomain(pulse::inventory::InventoryEngine* engine,
                pulse::ipc::InventoryDomainId domain) {
  pulse::inventory::CollectRequest req;
  req.domain = domain;
  req.force_refresh = true;
  // Cap large catalogs for readable spot-check dumps.
  req.limit = (domain == pulse::ipc::InventoryDomainId::Services ||
               domain == pulse::ipc::InventoryDomainId::Drivers ||
               domain == pulse::ipc::InventoryDomainId::Software)
                  ? 8
                  : 0;
  const auto snap = engine->GetDomain(req);
  std::cout << "DOMAIN " << static_cast<unsigned>(domain)
            << " status=" << StatusName(snap.status)
            << " gen=" << snap.generation
            << " detail=" << snap.status_detail << "\n";

  for (const auto& e : snap.services) {
    std::cout << "  service id=" << e.id << " state=" << e.state << "\n";
  }
  for (const auto& e : snap.drivers) {
    std::cout << "  driver id=" << e.id << " state=" << e.state << "\n";
  }
  for (const auto& e : snap.software) {
    std::cout << "  software id=" << e.id << " name=" << e.display_name
              << "\n";
  }
  for (const auto& e : snap.usb) {
    std::cout << "  usb id=" << e.id << " desc=" << e.description << "\n";
  }
  for (const auto& e : snap.pci) {
    std::cout << "  pci id=" << e.id << " desc=" << e.description << "\n";
  }
  for (const auto& e : snap.displays) {
    std::cout << "  display id=" << e.id << " desc=" << e.description
              << "\n";
  }
  for (const auto& e : snap.audio) {
    std::cout << "  audio id=" << e.id << " desc=" << e.description << "\n";
  }
  for (const auto& e : snap.bluetooth) {
    std::cout << "  bluetooth id=" << e.id << " desc=" << e.description
              << "\n";
  }
  for (const auto& e : snap.printers) {
    std::cout << "  printer id=" << e.id << " driver=" << e.driver_name
              << "\n";
  }
  for (const auto& e : snap.batteries) {
    std::cout << "  battery id=" << e.id << " desc=" << e.description
              << "\n";
  }
  for (const auto& e : snap.motherboard) {
    std::cout << "  motherboard id=" << e.id
              << " mfg=" << e.manufacturer << " product=" << e.product
              << " ver=" << e.version << "\n";
  }
  for (const auto& e : snap.bios) {
    std::cout << "  bios id=" << e.id << " vendor=" << e.vendor
              << " ver=" << e.version << " date=" << e.release_date << "\n";
  }
  for (const auto& e : snap.cpu) {
    std::cout << "  cpu id=" << e.id << " name=" << e.name
              << " cores=" << e.physical_cores
              << " logical=" << e.logical_processors
              << " arch=" << e.architecture << "\n";
  }
  for (const auto& e : snap.memory_modules) {
    std::cout << "  memory id=" << e.id << " bank=" << e.bank_locator
              << " size=" << e.size_bytes << " mfg=" << e.manufacturer
              << " part=" << e.part_number
              << " populated=" << (e.populated ? 1 : 0) << "\n";
  }
  for (const auto& e : snap.storage) {
    std::cout << "  storage id=" << e.id << " model=" << e.model
              << " size=" << e.size_bytes << " bus=" << e.bus_type
              << " path=" << e.device_path << "\n";
  }
  for (const auto& e : snap.network_adapters) {
    std::cout << "  network id=" << e.id << " name=" << e.friendly_name
              << " desc=" << e.description << " mac=" << e.mac_address
              << " status=" << e.operational_status << "\n";
  }
}

}  // namespace

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
      pulse::ipc::InventoryDomainId::Motherboard,
      pulse::ipc::InventoryDomainId::Bios,
      pulse::ipc::InventoryDomainId::Cpu,
      pulse::ipc::InventoryDomainId::MemoryModules,
      pulse::ipc::InventoryDomainId::Storage,
      pulse::ipc::InventoryDomainId::NetworkAdapters,
  };
  for (const auto d : domains) {
    DumpDomain(&engine, d);
  }
  return 0;
}
