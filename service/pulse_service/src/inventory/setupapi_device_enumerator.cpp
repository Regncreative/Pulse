#include "inventory/setupapi_device_enumerator.hpp"

#include "windows/wevt_helpers.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <SetupAPI.h>
#include <cfgmgr32.h>

#include <vector>

#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "cfgmgr32.lib")

namespace pulse::inventory {
namespace {

std::string ReadRegistryPropertyString(HDEVINFO set, SP_DEVINFO_DATA* info,
                                       DWORD property) {
  wchar_t buffer[1024]{};
  DWORD type = 0;
  DWORD needed = 0;
  if (!SetupDiGetDeviceRegistryPropertyW(
          set, info, property, &type, reinterpret_cast<PBYTE>(buffer),
          sizeof(buffer), &needed)) {
    return {};
  }
  if (type == REG_SZ || type == REG_EXPAND_SZ) {
    return wevt::WideToUtf8(buffer);
  }
  if (type == REG_MULTI_SZ) {
    return wevt::WideToUtf8(buffer);
  }
  return {};
}

std::string ReadInstanceId(HDEVINFO set, SP_DEVINFO_DATA* info,
                           bool* used_cfgmgr) {
  wchar_t buffer[512]{};
  DWORD needed = 0;
  if (SetupDiGetDeviceInstanceIdW(set, info, buffer, 512, &needed)) {
    return wevt::WideToUtf8(buffer);
  }

  WCHAR cm_id[MAX_DEVICE_ID_LEN]{};
  const CONFIGRET cr =
      CM_Get_Device_IDW(info->DevInst, cm_id, MAX_DEVICE_ID_LEN, 0);
  if (cr == CR_SUCCESS && cm_id[0] != L'\0') {
    if (used_cfgmgr) *used_cfgmgr = true;
    return wevt::WideToUtf8(cm_id);
  }
  return {};
}

void ReadProblemCode(SP_DEVINFO_DATA* info, SetupApiDeviceRow* row) {
  ULONG status = 0;
  ULONG problem = 0;
  if (CM_Get_DevNode_Status(&status, &problem, info->DevInst, 0) ==
      CR_SUCCESS) {
    if ((status & DN_HAS_PROBLEM) != 0) {
      row->has_problem_code = true;
      row->problem_code = problem;
    }
  }
}

SetupApiEnumResult EnumerateDevInfoSet(HDEVINFO set, std::uint32_t limit) {
  SetupApiEnumResult out;
  if (set == INVALID_HANDLE_VALUE) {
    const DWORD err = GetLastError();
    if (err == ERROR_ACCESS_DENIED) {
      out.access_denied = true;
      out.status_detail = "SetupDiGetClassDevsW access denied";
    } else {
      out.error = true;
      out.status_detail = "SetupDiGetClassDevsW failed";
    }
    return out;
  }

  SP_DEVINFO_DATA info{};
  info.cbSize = sizeof(info);
  for (DWORD index = 0; SetupDiEnumDeviceInfo(set, index, &info); ++index) {
    if (out.rows.size() >= limit) {
      out.truncated = true;
      break;
    }

    SetupApiDeviceRow row;
    bool cfgmgr = false;
    row.instance_id = ReadInstanceId(set, &info, &cfgmgr);
    if (cfgmgr) out.used_cfgmgr_fallback = true;
    if (row.instance_id.empty()) {
      continue;
    }

    row.description = ReadRegistryPropertyString(set, &info, SPDRP_FRIENDLYNAME);
    if (row.description.empty()) {
      row.description =
          ReadRegistryPropertyString(set, &info, SPDRP_DEVICEDESC);
    }
    row.hardware_id =
        ReadRegistryPropertyString(set, &info, SPDRP_HARDWAREID);
    row.manufacturer = ReadRegistryPropertyString(set, &info, SPDRP_MFG);
    row.service = ReadRegistryPropertyString(set, &info, SPDRP_SERVICE);
    row.class_name = ReadRegistryPropertyString(set, &info, SPDRP_CLASS);
    row.class_guid = ReadRegistryPropertyString(set, &info, SPDRP_CLASSGUID);
    row.location_info =
        ReadRegistryPropertyString(set, &info, SPDRP_LOCATION_INFORMATION);
    ReadProblemCode(&info, &row);
    out.rows.push_back(std::move(row));
  }

  SetupDiDestroyDeviceInfoList(set);
  return out;
}

}  // namespace

SetupApiEnumResult EnumeratePresentByEnumerator(const wchar_t* enumerator,
                                                std::uint32_t limit) {
  if (enumerator == nullptr || enumerator[0] == L'\0' || limit == 0) {
    SetupApiEnumResult out;
    out.error = true;
    out.status_detail = "Invalid SetupAPI enumerator request";
    return out;
  }

  const HDEVINFO set = SetupDiGetClassDevsW(
      nullptr, enumerator, nullptr, DIGCF_PRESENT | DIGCF_ALLCLASSES);
  return EnumerateDevInfoSet(set, limit);
}

SetupApiEnumResult EnumeratePresentByClassGuid(const GUID& class_guid,
                                               std::uint32_t limit) {
  if (limit == 0) {
    SetupApiEnumResult out;
    out.error = true;
    out.status_detail = "Invalid SetupAPI class GUID request";
    return out;
  }

  const HDEVINFO set =
      SetupDiGetClassDevsW(&class_guid, nullptr, nullptr, DIGCF_PRESENT);
  return EnumerateDevInfoSet(set, limit);
}

bool ResolveSetupClassGuid(const wchar_t* class_name, GUID* out_guid) {
  if (class_name == nullptr || class_name[0] == L'\0' || out_guid == nullptr) {
    return false;
  }
  GUID guid{};
  DWORD required = 0;
  if (!SetupDiClassGuidsFromNameW(class_name, &guid, 1, &required)) {
    return false;
  }
  *out_guid = guid;
  return true;
}

}  // namespace pulse::inventory
