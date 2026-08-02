#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <guiddef.h>

namespace pulse::inventory {

/// Shared SetupAPI read helpers for Inventory device domains (ADR-011).
/// Not a collector — domain collectors own membership and status.
struct SetupApiDeviceRow {
  std::string instance_id;       // stable id
  std::string description;       // SPDRP_FRIENDLYNAME or SPDRP_DEVICEDESC
  std::string hardware_id;       // first multi-sz HardwareID
  std::string manufacturer;      // SPDRP_MFG
  std::string service;           // SPDRP_SERVICE
  std::string class_name;        // SPDRP_CLASS
  std::string class_guid;        // SPDRP_CLASSGUID
  std::string location_info;     // SPDRP_LOCATION_INFORMATION
  std::uint32_t problem_code = 0;
  bool has_problem_code = false;
};

struct SetupApiEnumResult {
  bool access_denied = false;
  bool error = false;
  std::string status_detail;
  bool truncated = false;
  bool used_cfgmgr_fallback = false;
  std::vector<SetupApiDeviceRow> rows;
};

/// Enumerate present devices by PnP enumerator (e.g. L"USB", L"PCI").
[[nodiscard]] SetupApiEnumResult EnumeratePresentByEnumerator(
    const wchar_t* enumerator, std::uint32_t limit);

/// Enumerate present devices by device setup class GUID (DIGCF_PRESENT).
[[nodiscard]] SetupApiEnumResult EnumeratePresentByClassGuid(
    const GUID& class_guid, std::uint32_t limit);

/// Resolve a setup class name (e.g. L"Monitor") to its GUID via SetupAPI.
[[nodiscard]] bool ResolveSetupClassGuid(const wchar_t* class_name,
                                         GUID* out_guid);

}  // namespace pulse::inventory
