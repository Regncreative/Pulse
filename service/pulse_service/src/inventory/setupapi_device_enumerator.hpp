#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace pulse::inventory {

/// Shared SetupAPI read helpers for Inventory device domains (ADR-011).
/// Not a collector — USB/PCI collectors own membership and status.
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
/// Primary: SetupDiGetClassDevsW(enumerator). Fallback id: CM_Get_Device_IDW.
[[nodiscard]] SetupApiEnumResult EnumeratePresentByEnumerator(
    const wchar_t* enumerator, std::uint32_t limit);

}  // namespace pulse::inventory
