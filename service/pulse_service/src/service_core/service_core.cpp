#include "service_core/service_core.hpp"

#include "collector/event_engine.hpp"
#include "logging/logger.hpp"
#include "pulse/constants.hpp"

#include <atomic>
#include <iostream>
#include <string>

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

namespace pulse {
namespace {

SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status{};
ServiceCore* g_core = nullptr;
std::atomic<bool> g_stop_console{false};

void ReportStatus(DWORD state, DWORD exit_code = NO_ERROR, DWORD wait_hint_ms = 0) {
  static DWORD checkpoint = 1;
  g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_status.dwCurrentState = state;
  g_status.dwWin32ExitCode = exit_code;
  g_status.dwWaitHint = wait_hint_ms;
  if (state == SERVICE_START_PENDING || state == SERVICE_STOP_PENDING) {
    g_status.dwControlsAccepted = 0;
    g_status.dwCheckPoint = checkpoint++;
  } else {
    g_status.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
    g_status.dwCheckPoint = 0;
  }
  if (g_status_handle) {
    SetServiceStatus(g_status_handle, &g_status);
  }
}

DWORD WINAPI ServiceCtrlHandler(DWORD control, DWORD, LPVOID, LPVOID) {
  switch (control) {
    case SERVICE_CONTROL_STOP:
    case SERVICE_CONTROL_SHUTDOWN:
      ReportStatus(SERVICE_STOP_PENDING, NO_ERROR, 10000);
      if (g_core) g_core->Stop();
      return NO_ERROR;
    default:
      return ERROR_CALL_NOT_IMPLEMENTED;
  }
}

BOOL WINAPI ConsoleCtrlHandler(DWORD type) {
  if (type == CTRL_C_EVENT || type == CTRL_CLOSE_EVENT || type == CTRL_BREAK_EVENT) {
    g_stop_console = true;
    return TRUE;
  }
  return FALSE;
}

bool BootstrapFromDisk(ServiceConfig* config) {
  std::string err;
  const auto cfg_path = DefaultProgramDataPulseDir() + L"\\config.json";
  WriteDefaultConfigIfMissing(cfg_path, &err);
  if (!LoadConfig(cfg_path, config, &err)) {
    Logger::Instance().Error("ServiceCore", "Config load failed: " + err);
    return false;
  }
  if (!EnsureDataDirectories(*config, &err)) {
    Logger::Instance().Error("ServiceCore", "Data dirs failed: " + err);
    return false;
  }
  Logger::Instance().SetLogDirectory(config->log_dir);
  if (config->log_level == "debug") {
    Logger::Instance().SetLevel(LogLevel::Debug);
  }
  return true;
}

void WINAPI ServiceMain(DWORD, LPWSTR*) {
  g_status_handle =
      RegisterServiceCtrlHandlerExW(L"PulseService", ServiceCtrlHandler, nullptr);
  if (!g_status_handle) return;

  ReportStatus(SERVICE_START_PENDING, NO_ERROR, 5000);

  ServiceConfig config = DefaultConfig();
  if (!BootstrapFromDisk(&config)) {
    ReportStatus(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR);
    return;
  }

  ServiceCore core;
  g_core = &core;
  if (!core.Initialize(config)) {
    g_core = nullptr;
    ReportStatus(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR);
    return;
  }
  core.SetRunMode("Windows Service");
  if (!core.Start()) {
    g_core = nullptr;
    ReportStatus(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR);
    return;
  }
  ReportStatus(SERVICE_RUNNING);
  Logger::Instance().Info("ServiceCore", "PulseService running");

  while (core.IsRunning()) {
    Sleep(200);
  }

  g_core = nullptr;
  ReportStatus(SERVICE_STOPPED);
}

}  // namespace

bool ServiceCore::Initialize(const ServiceConfig& config) {
  config_ = config;
  collector_ = std::make_unique<Collector>();
  ipc_ = std::make_unique<IpcServer>(config_.pipe_name, config_.live_queue_capacity);
  EventEnginePlaceholder engine;
  Logger::Instance().Info("ServiceCore",
                          std::string("Initialized placeholder ") + engine.Name());
  return true;
}

void ServiceCore::SetRunMode(std::string mode) {
  if (ipc_) ipc_->SetRunMode(std::move(mode));
}

bool ServiceCore::Start() {
  if (!collector_->Start()) return false;
  if (!ipc_->Start()) return false;
  running_ = true;
  return true;
}

void ServiceCore::Stop() {
  if (!running_.exchange(false)) return;
  Logger::Instance().Info("ServiceCore", "Stopping");
  if (ipc_) ipc_->Stop();
  if (collector_) collector_->Stop();
}

int InstallService() {
  wchar_t path[MAX_PATH];
  if (!GetModuleFileNameW(nullptr, path, MAX_PATH)) return 1;

  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE);
  if (!scm) {
    std::wcerr << L"OpenSCManager failed. Run as Administrator.\n";
    return 1;
  }

  SC_HANDLE svc = CreateServiceW(
      scm, L"PulseService", L"Pulse", SERVICE_ALL_ACCESS, SERVICE_WIN32_OWN_PROCESS,
      SERVICE_DEMAND_START, SERVICE_ERROR_NORMAL, path, nullptr, nullptr, nullptr,
      L"NT AUTHORITY\\LocalService", nullptr);
  if (!svc) {
    const DWORD err = GetLastError();
    CloseServiceHandle(scm);
    if (err == ERROR_SERVICE_EXISTS) {
      std::wcout << L"PulseService already installed.\n";
      return 0;
    }
    std::wcerr << L"CreateService failed: " << err << L"\n";
    return 1;
  }

  SERVICE_DESCRIPTIONW desc{};
  wchar_t text[] = L"Read-only Windows diagnostics collector for Pulse";
  desc.lpDescription = text;
  ChangeServiceConfig2W(svc, SERVICE_CONFIG_DESCRIPTION, &desc);

  CloseServiceHandle(svc);
  CloseServiceHandle(scm);
  std::wcout << L"PulseService installed.\n";
  return 0;
}

int UninstallService() {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return 1;
  SC_HANDLE svc = OpenServiceW(scm, L"PulseService", SERVICE_STOP | DELETE);
  if (!svc) {
    CloseServiceHandle(scm);
    std::wcerr << L"OpenService failed.\n";
    return 1;
  }
  SERVICE_STATUS status{};
  ControlService(svc, SERVICE_CONTROL_STOP, &status);
  if (!DeleteService(svc)) {
    std::wcerr << L"DeleteService failed.\n";
    CloseServiceHandle(svc);
    CloseServiceHandle(scm);
    return 1;
  }
  CloseServiceHandle(svc);
  CloseServiceHandle(scm);
  std::wcout << L"PulseService uninstalled.\n";
  return 0;
}

int RunConsoleMode(int, wchar_t**) {
  SetConsoleCtrlHandler(ConsoleCtrlHandler, TRUE);
  ServiceConfig config = DefaultConfig();
  if (!BootstrapFromDisk(&config)) return 1;

  ServiceCore core;
  if (!core.Initialize(config)) return 1;
  core.SetRunMode("Console");
  if (!core.Start()) return 1;
  Logger::Instance().Info("ServiceCore", "Console mode running. Ctrl+C to stop.");
  std::wcout << L"PulseService console mode. Pipe: \\\\.\\pipe\\PulseService\n";
  std::wcout << L"Historical Timeline snapshot available via GetTimelineSnapshot (System).\n";

  while (!g_stop_console && core.IsRunning()) {
    Sleep(200);
  }
  core.Stop();
  Logger::Instance().Info("ServiceCore", "Console mode stopped");
  return 0;
}

int RunServiceMode() {
  SERVICE_TABLE_ENTRYW table[] = {
      {const_cast<LPWSTR>(L"PulseService"), ServiceMain},
      {nullptr, nullptr},
  };
  if (!StartServiceCtrlDispatcherW(table)) {
    std::wcerr << L"StartServiceCtrlDispatcher failed. Use --console for interactive.\n";
    return 1;
  }
  return 0;
}

}  // namespace pulse
