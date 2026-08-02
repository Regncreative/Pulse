#include "inventory/smbios_table.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <cstring>

namespace pulse::inventory {
namespace {

// --- Small string helpers (mirrors system_overview_info.cpp; not shared via
// a header today) ---

std::string TrimCopy(std::string s) {
  while (!s.empty() &&
         (s.back() == ' ' || s.back() == '\t' || s.back() == '\0')) {
    s.pop_back();
  }
  size_t i = 0;
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t')) ++i;
  return s.substr(i);
}

uint8_t SmbiosReadU8(const uint8_t* base, uint8_t length, size_t offset) {
  if (offset + sizeof(uint8_t) > length) return 0;
  return base[offset];
}

uint16_t SmbiosReadU16(const uint8_t* base, uint8_t length, size_t offset) {
  if (offset + sizeof(uint16_t) > length) return 0;
  uint16_t v = 0;
  memcpy(&v, base + offset, sizeof(v));
  return v;
}

uint32_t SmbiosReadU32(const uint8_t* base, uint8_t length, size_t offset) {
  if (offset + sizeof(uint32_t) > length) return 0;
  uint32_t v = 0;
  memcpy(&v, base + offset, sizeof(v));
  return v;
}

bool SmbiosHasField(uint8_t length, size_t offset, size_t size) {
  return offset + size <= length;
}

/// Reads the (1-based) `index`th string from a structure's trailing string
/// table. Returns empty for index 0 (no string) or out-of-range access.
std::string SmbiosStringAt(const uint8_t* struct_start, uint8_t formatted_length,
                           const uint8_t* table_end, uint8_t index) {
  if (index == 0) return {};
  const uint8_t* p = struct_start + formatted_length;
  uint8_t current = 1;
  while (p < table_end && *p != 0) {
    const auto* s = reinterpret_cast<const char*>(p);
    const size_t max_len = static_cast<size_t>(table_end - p);
    const size_t len = strnlen(s, max_len);
    if (current == index) return std::string(s, len);
    p += len + 1;
    ++current;
  }
  return {};
}

/// Advances past a structure's formatted area and trailing (double-null
/// terminated) string set to the next structure header.
const uint8_t* SmbiosNextStructure(const uint8_t* struct_start,
                                   uint8_t formatted_length,
                                   const uint8_t* table_end) {
  const uint8_t* p = struct_start + formatted_length;
  while (p + 1 < table_end && !(p[0] == 0 && p[1] == 0)) ++p;
  return (p + 2 <= table_end) ? p + 2 : table_end;
}

std::string BoardTypeName(uint8_t code) {
  switch (code) {
    case 0x01: return "Unknown";
    case 0x02: return "Other";
    case 0x03: return "Server Blade";
    case 0x04: return "Connectivity Switch";
    case 0x05: return "System Management Module";
    case 0x06: return "Processor Module";
    case 0x07: return "I/O Module";
    case 0x08: return "Memory Module";
    case 0x09: return "Daughter Board";
    case 0x0A: return "Motherboard";
    case 0x0B: return "Processor/Memory Module";
    case 0x0C: return "Processor/IO Module";
    case 0x0D: return "Interconnect Board";
    default: return "";
  }
}

std::string MemoryFormFactorName(uint8_t code) {
  switch (code) {
    case 0x01: return "Other";
    case 0x02: return "Unknown";
    case 0x03: return "SIMM";
    case 0x04: return "SIP";
    case 0x05: return "Chip";
    case 0x06: return "DIP";
    case 0x07: return "ZIP";
    case 0x08: return "Proprietary Card";
    case 0x09: return "DIMM";
    case 0x0A: return "TSOP";
    case 0x0B: return "Row of Chips";
    case 0x0C: return "RIMM";
    case 0x0D: return "SODIMM";
    case 0x0E: return "SRIMM";
    case 0x0F: return "FB-DIMM";
    case 0x10: return "Die";
    case 0x11: return "CAMM";
    default: return "";
  }
}

/// SMBIOS Type 17 "Memory Type" (Table 78). Values not listed are left
/// unset rather than guessed.
std::string MemoryTypeName(uint8_t code) {
  switch (code) {
    case 0x03: return "DRAM";
    case 0x0F: return "SDRAM";
    case 0x12: return "DDR";
    case 0x13: return "DDR2";
    case 0x14: return "DDR2 FB-DIMM";
    case 0x18: return "DDR3";
    case 0x1A: return "DDR4";
    case 0x1B: return "LPDDR";
    case 0x1C: return "LPDDR2";
    case 0x1D: return "LPDDR3";
    case 0x1E: return "LPDDR4";
    case 0x20: return "HBM";
    case 0x21: return "HBM2";
    case 0x22: return "DDR5";
    case 0x23: return "LPDDR5";
    case 0x24: return "HBM3";
    default: return "";
  }
}

/// BIOS ROM size in bytes from the legacy byte field (offset 0x09) and,
/// when it signals overflow (0xFF), the Extended BIOS ROM Size word
/// (offset 0x18; top 2 bits select MB/GB unit, low 14 bits are the count).
uint64_t BiosRomSizeBytes(uint8_t legacy_byte, uint16_t extended_word,
                          bool has_extended) {
  if (legacy_byte != 0xFF) {
    return (static_cast<uint64_t>(legacy_byte) + 1ULL) * 64ULL * 1024ULL;
  }
  if (!has_extended || extended_word == 0) return 0;
  const uint16_t unit = static_cast<uint16_t>(extended_word >> 14);
  const uint64_t count = extended_word & 0x3FFF;
  const uint64_t unit_bytes = (unit == 1) ? (1ULL << 30) : (1ULL << 20);
  return count * unit_bytes;
}

void ParseBiosStructure(const uint8_t* p, uint8_t length,
                        const uint8_t* table_end, ipc::InventoryBiosEntry* out) {
  out->id = "bios";
  out->vendor = TrimCopy(SmbiosStringAt(p, length, table_end, SmbiosReadU8(p, length, 0x04)));
  out->version = TrimCopy(SmbiosStringAt(p, length, table_end, SmbiosReadU8(p, length, 0x05)));
  out->release_date = TrimCopy(SmbiosStringAt(p, length, table_end, SmbiosReadU8(p, length, 0x08)));

  if (SmbiosHasField(length, 0x14, 1)) {
    const uint8_t major = SmbiosReadU8(p, length, 0x14);
    if (major != 0xFF) {
      out->major_release = major;
      out->has_major_release = true;
    }
  }
  if (SmbiosHasField(length, 0x15, 1)) {
    const uint8_t minor = SmbiosReadU8(p, length, 0x15);
    if (minor != 0xFF) {
      out->minor_release = minor;
      out->has_minor_release = true;
    }
  }

  const uint8_t rom_size_byte = SmbiosReadU8(p, length, 0x09);
  const bool has_extended = SmbiosHasField(length, 0x18, 2);
  const uint16_t extended_word = has_extended ? SmbiosReadU16(p, length, 0x18) : 0;
  const uint64_t rom_bytes = BiosRomSizeBytes(rom_size_byte, extended_word, has_extended);
  if (rom_bytes > 0) {
    out->rom_size_bytes = rom_bytes;
    out->has_rom_size_bytes = true;
  }

  if (SmbiosHasField(length, 0x13, 1)) {
    const uint8_t ext_byte2 = SmbiosReadU8(p, length, 0x13);
    out->uefi_capable = (ext_byte2 & (1 << 3)) != 0;
    out->has_uefi_capable = true;
  }
}

void ParseBaseboardStructure(const uint8_t* p, uint8_t length,
                             const uint8_t* table_end,
                             ipc::InventoryMotherboardEntry* out) {
  out->id = "motherboard";
  out->manufacturer = TrimCopy(SmbiosStringAt(p, length, table_end, SmbiosReadU8(p, length, 0x04)));
  out->product = TrimCopy(SmbiosStringAt(p, length, table_end, SmbiosReadU8(p, length, 0x05)));
  out->version = TrimCopy(SmbiosStringAt(p, length, table_end, SmbiosReadU8(p, length, 0x06)));
  out->serial_number = TrimCopy(SmbiosStringAt(p, length, table_end, SmbiosReadU8(p, length, 0x07)));
  out->asset_tag = TrimCopy(SmbiosStringAt(p, length, table_end, SmbiosReadU8(p, length, 0x08)));
  if (SmbiosHasField(length, 0x0A, 1)) {
    out->location_in_chassis =
        TrimCopy(SmbiosStringAt(p, length, table_end, SmbiosReadU8(p, length, 0x0A)));
  }
  if (SmbiosHasField(length, 0x0D, 1)) {
    const std::string board_type = BoardTypeName(SmbiosReadU8(p, length, 0x0D));
    if (!board_type.empty()) out->board_type = board_type;
  }
}

void ParseMemoryDeviceStructure(const uint8_t* p, uint8_t length,
                                const uint8_t* table_end,
                                ipc::InventoryMemoryModuleEntry* out) {
  const uint8_t locator_idx = SmbiosReadU8(p, length, 0x10);
  const uint8_t bank_idx = SmbiosReadU8(p, length, 0x11);
  const std::string device_locator =
      TrimCopy(SmbiosStringAt(p, length, table_end, locator_idx));
  out->bank_locator = TrimCopy(SmbiosStringAt(p, length, table_end, bank_idx));
  // ADR-011: id = Locator. Combine bank + device locator when both exist so
  // dual-channel DIMMs that share "DIMM 0" remain unique and stable.
  if (!out->bank_locator.empty() && !device_locator.empty()) {
    out->id = out->bank_locator + "|" + device_locator;
  } else if (!device_locator.empty()) {
    out->id = device_locator;
  } else if (!out->bank_locator.empty()) {
    out->id = out->bank_locator;
  }

  const uint16_t size_word = SmbiosReadU16(p, length, 0x0C);
  const bool populated = (size_word != 0 && size_word != 0xFFFF);
  out->populated = populated;
  if (!populated) return;

  uint64_t size_bytes = 0;
  if (size_word == 0x7FFF && SmbiosHasField(length, 0x1C, 4)) {
    // Extended Size field: bits 0-30 are size in MB.
    const uint32_t extended = SmbiosReadU32(p, length, 0x1C) & 0x7FFFFFFF;
    size_bytes = static_cast<uint64_t>(extended) * 1024ULL * 1024ULL;
  } else {
    const bool kilobyte_granularity = (size_word & 0x8000) != 0;
    const uint64_t raw = size_word & 0x7FFF;
    size_bytes = kilobyte_granularity ? raw * 1024ULL : raw * 1024ULL * 1024ULL;
  }
  if (size_bytes > 0) {
    out->size_bytes = size_bytes;
    out->has_size_bytes = true;
  }

  const uint16_t total_width = SmbiosReadU16(p, length, 0x08);
  const uint16_t data_width = SmbiosReadU16(p, length, 0x0A);
  if (total_width != 0 && total_width != 0xFFFF) {
    out->total_width_bits = total_width;
    out->has_total_width_bits = true;
  }
  if (data_width != 0 && data_width != 0xFFFF) {
    out->data_width_bits = data_width;
    out->has_data_width_bits = true;
  }
  if (out->has_total_width_bits && out->has_data_width_bits) {
    out->is_ecc = out->total_width_bits > out->data_width_bits;
    out->has_is_ecc = true;
  }

  const uint8_t form_factor_code = SmbiosReadU8(p, length, 0x0E);
  const std::string form_factor = MemoryFormFactorName(form_factor_code);
  if (!form_factor.empty()) out->form_factor = form_factor;

  const uint8_t memory_type_code = SmbiosReadU8(p, length, 0x12);
  const std::string memory_type = MemoryTypeName(memory_type_code);
  if (!memory_type.empty()) out->memory_type = memory_type;

  const uint16_t speed =
      SmbiosHasField(length, 0x15, 2) ? SmbiosReadU16(p, length, 0x15) : 0;
  const uint32_t extended_speed =
      SmbiosHasField(length, 0x54, 4) ? SmbiosReadU32(p, length, 0x54) : 0;
  if (speed != 0 && speed != 0xFFFF) {
    out->speed_mts = speed;
    out->has_speed_mts = true;
  } else if (extended_speed != 0) {
    out->speed_mts = extended_speed;
    out->has_speed_mts = true;
  }

  const uint16_t configured_speed =
      SmbiosHasField(length, 0x20, 2) ? SmbiosReadU16(p, length, 0x20) : 0;
  const uint32_t extended_configured_speed =
      SmbiosHasField(length, 0x58, 4) ? SmbiosReadU32(p, length, 0x58) : 0;
  if (configured_speed != 0 && configured_speed != 0xFFFF) {
    out->configured_speed_mts = configured_speed;
    out->has_configured_speed_mts = true;
  } else if (extended_configured_speed != 0) {
    out->configured_speed_mts = extended_configured_speed;
    out->has_configured_speed_mts = true;
  }

  if (SmbiosHasField(length, 0x26, 2)) {
    const uint16_t configured_voltage = SmbiosReadU16(p, length, 0x26);
    if (configured_voltage != 0) {
      out->configured_voltage_mv = configured_voltage;
      out->has_configured_voltage_mv = true;
    }
  }

  const uint8_t manufacturer_idx =
      SmbiosHasField(length, 0x17, 1) ? SmbiosReadU8(p, length, 0x17) : 0;
  const uint8_t serial_idx =
      SmbiosHasField(length, 0x18, 1) ? SmbiosReadU8(p, length, 0x18) : 0;
  const uint8_t part_idx =
      SmbiosHasField(length, 0x1A, 1) ? SmbiosReadU8(p, length, 0x1A) : 0;

  const std::string manufacturer =
      TrimCopy(SmbiosStringAt(p, length, table_end, manufacturer_idx));
  if (!manufacturer.empty()) out->manufacturer = manufacturer;

  const std::string serial = TrimCopy(SmbiosStringAt(p, length, table_end, serial_idx));
  if (!serial.empty()) out->serial_number = serial;

  const std::string part_number = TrimCopy(SmbiosStringAt(p, length, table_end, part_idx));
  if (!part_number.empty()) out->part_number = part_number;
}

}  // namespace

SmbiosTable ReadSmbiosTable() {
  SmbiosTable out;

  const DWORD signature = 'RSMB';
  const DWORD needed = GetSystemFirmwareTable(signature, 0, nullptr, 0);
  if (needed == 0) {
    out.status_detail = "GetSystemFirmwareTable(RSMB) unavailable on this platform";
    return out;
  }

  std::vector<uint8_t> buffer(needed);
  if (GetSystemFirmwareTable(signature, 0, buffer.data(),
                             static_cast<DWORD>(buffer.size())) != needed) {
    out.status_detail = "GetSystemFirmwareTable(RSMB) read failed";
    return out;
  }
  if (buffer.size() < 8) {
    out.status_detail = "SMBIOS firmware table too small";
    return out;
  }

  uint32_t table_length = 0;
  memcpy(&table_length, buffer.data() + 4, sizeof(table_length));

  const uint8_t* table = buffer.data() + 8;
  const uint8_t* buffer_end = buffer.data() + buffer.size();
  const uint8_t* table_end = table + table_length;
  if (table_end > buffer_end) table_end = buffer_end;
  if (table >= table_end) {
    out.status_detail = "SMBIOS structure table empty";
    return out;
  }

  out.available = true;

  const uint8_t* p = table;
  while (p + 4 <= table_end) {
    const uint8_t type = p[0];
    const uint8_t length = p[1];
    if (length < 4) break;  // malformed structure
    if (type == 127) break;  // End-of-Table marker

    if (type == 0 && !out.has_bios) {
      ParseBiosStructure(p, length, table_end, &out.bios);
      out.has_bios = true;
    } else if (type == 2 && !out.has_motherboard) {
      ParseBaseboardStructure(p, length, table_end, &out.motherboard);
      out.has_motherboard = true;
    } else if (type == 17) {
      ipc::InventoryMemoryModuleEntry entry;
      ParseMemoryDeviceStructure(p, length, table_end, &entry);
      if (!entry.id.empty()) {
        out.memory_modules.push_back(std::move(entry));
      }
    }

    p = SmbiosNextStructure(p, length, table_end);
  }

  return out;
}

}  // namespace pulse::inventory
