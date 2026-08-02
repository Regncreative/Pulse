#pragma once

#include "pulse_wire.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Single read of GetSystemFirmwareTable('RSMB'), parsed once into
/// motherboard (Type 2), BIOS (Type 0), and memory module (Type 17) view
/// structs (ADR-011: one RSMB read helper projects three P2 domains).
struct SmbiosTable {
  bool available = false;
  std::string status_detail;

  bool has_motherboard = false;
  ipc::InventoryMotherboardEntry motherboard;

  bool has_bios = false;
  ipc::InventoryBiosEntry bios;

  // One entry per SMBIOS Type 17 structure, including unpopulated slots
  // (Type 17 structures exist per physical DIMM slot regardless of whether
  // it holds a module; `populated` distinguishes them).
  std::vector<ipc::InventoryMemoryModuleEntry> memory_modules;
};

/// Reads and parses the SMBIOS firmware table once. Safe to call repeatedly;
/// callers own their own TTL/caching (ADR-011 D3).
[[nodiscard]] SmbiosTable ReadSmbiosTable();

}  // namespace pulse::inventory
