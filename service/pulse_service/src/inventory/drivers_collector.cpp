#include "inventory/drivers_collector.hpp"

#include "windows/wevt_helpers.hpp"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <winsvc.h>

#include <vector>

namespace pulse::inventory {
namespace {

std::string ServiceStateName(DWORD state) {
  switch (state) {
    case SERVICE_STOPPED:
      return "stopped";
    case SERVICE_START_PENDING:
      return "start_pending";
    case SERVICE_STOP_PENDING:
      return "stop_pending";
    case SERVICE_RUNNING:
      return "running";
    case SERVICE_CONTINUE_PENDING:
      return "continue_pending";
    case SERVICE_PAUSE_PENDING:
      return "pause_pending";
    case SERVICE_PAUSED:
      return "paused";
    default:
      return "unknown";
  }
}

std::string StartTypeName(DWORD start_type) {
  switch (start_type) {
    case SERVICE_BOOT_START:
      return "boot";
    case SERVICE_SYSTEM_START:
      return "system";
    case SERVICE_AUTO_START:
      return "automatic";
    case SERVICE_DEMAND_START:
      return "manual";
    case SERVICE_DISABLED:
      return "disabled";
    default:
      return "unknown";
  }
}

std::string DriverTypeName(DWORD service_type) {
  const DWORD kind = service_type & 0xF;
  switch (kind) {
    case SERVICE_KERNEL_DRIVER:
      return "kernel";
    case SERVICE_FILE_SYSTEM_DRIVER:
      return "file_system";
    case SERVICE_ADAPTER:
      return "adapter";
    case SERVICE_RECOGNIZER_DRIVER:
      return "recognizer";
    default:
      return "other";
  }
}

}  // namespace

DriversCollector::Result DriversCollector::Collect(std::uint32_t limit) {
  Result out;
  const std::uint32_t cap =
      limit == 0 ? kDefaultLimit : (limit > kDefaultLimit ? kDefaultLimit : limit);

  SC_HANDLE scm = OpenSCManagerW(
      nullptr, nullptr, SC_MANAGER_CONNECT | SC_MANAGER_ENUMERATE_SERVICE);
  if (scm == nullptr) {
    const DWORD err = GetLastError();
    if (err == ERROR_ACCESS_DENIED) {
      out.status = ipc::InventoryStatus::AccessDenied;
      out.status_detail = "OpenSCManager denied enumerate access";
    } else {
      out.status = ipc::InventoryStatus::Error;
      out.status_detail = "OpenSCManager failed";
    }
    return out;
  }

  DWORD bytes_needed = 0;
  DWORD services_returned = 0;
  DWORD resume = 0;
  EnumServicesStatusExW(scm, SC_ENUM_PROCESS_INFO, SERVICE_DRIVER,
                        SERVICE_STATE_ALL, nullptr, 0, &bytes_needed,
                        &services_returned, &resume, nullptr);
  if (GetLastError() != ERROR_MORE_DATA || bytes_needed == 0) {
    CloseServiceHandle(scm);
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "EnumServicesStatusExW size query failed";
    return out;
  }

  std::vector<std::uint8_t> buffer(bytes_needed);
  resume = 0;
  if (!EnumServicesStatusExW(scm, SC_ENUM_PROCESS_INFO, SERVICE_DRIVER,
                             SERVICE_STATE_ALL, buffer.data(),
                             static_cast<DWORD>(buffer.size()), &bytes_needed,
                             &services_returned, &resume, nullptr)) {
    CloseServiceHandle(scm);
    out.status = ipc::InventoryStatus::Error;
    out.status_detail = "EnumServicesStatusExW failed";
    return out;
  }

  auto* rows = reinterpret_cast<ENUM_SERVICE_STATUS_PROCESSW*>(buffer.data());
  bool config_gaps = false;
  for (DWORD i = 0; i < services_returned; ++i) {
    if (out.entries.size() >= cap) {
      out.truncated = true;
      break;
    }
    ipc::InventoryDriverEntry entry;
    entry.id = wevt::WideToUtf8(rows[i].lpServiceName ? rows[i].lpServiceName
                                                       : L"");
    if (entry.id.empty()) {
      continue;
    }
    entry.display_name = wevt::WideToUtf8(
        rows[i].lpDisplayName ? rows[i].lpDisplayName : L"");
    entry.state = ServiceStateName(rows[i].ServiceStatusProcess.dwCurrentState);

    SC_HANDLE svc =
        OpenServiceW(scm, rows[i].lpServiceName, SERVICE_QUERY_CONFIG);
    if (svc != nullptr) {
      DWORD cfg_needed = 0;
      QueryServiceConfigW(svc, nullptr, 0, &cfg_needed);
      if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && cfg_needed > 0) {
        std::vector<std::uint8_t> cfg_buf(cfg_needed);
        auto* cfg =
            reinterpret_cast<QUERY_SERVICE_CONFIGW*>(cfg_buf.data());
        if (QueryServiceConfigW(svc, cfg, cfg_needed, &cfg_needed)) {
          entry.start_type = StartTypeName(cfg->dwStartType);
          entry.binary_path =
              wevt::WideToUtf8(cfg->lpBinaryPathName ? cfg->lpBinaryPathName
                                                     : L"");
          entry.driver_type = DriverTypeName(cfg->dwServiceType);
        } else {
          config_gaps = true;
        }
      } else {
        config_gaps = true;
      }

      DWORD desc_needed = 0;
      QueryServiceConfig2W(svc, SERVICE_CONFIG_DESCRIPTION, nullptr, 0,
                           &desc_needed);
      if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && desc_needed > 0) {
        std::vector<std::uint8_t> desc_buf(desc_needed);
        if (QueryServiceConfig2W(svc, SERVICE_CONFIG_DESCRIPTION,
                                 desc_buf.data(), desc_needed, &desc_needed)) {
          auto* desc =
              reinterpret_cast<SERVICE_DESCRIPTIONW*>(desc_buf.data());
          if (desc->lpDescription != nullptr) {
            entry.description = wevt::WideToUtf8(desc->lpDescription);
          }
        }
      }
      CloseServiceHandle(svc);
    } else {
      config_gaps = true;
    }

    out.entries.push_back(std::move(entry));
  }

  CloseServiceHandle(scm);

  if (out.truncated || config_gaps) {
    out.status = ipc::InventoryStatus::Partial;
    if (out.truncated && config_gaps) {
      out.status_detail = "Driver list truncated and some configs unavailable";
    } else if (out.truncated) {
      out.status_detail = "Driver list truncated at collector limit";
    } else {
      out.status_detail = "Some driver configs were unavailable";
    }
  } else {
    out.status = ipc::InventoryStatus::Available;
  }
  return out;
}

}  // namespace pulse::inventory
