#include "service_core/service_core.hpp"

#include "logging/logger.hpp"
#include "pulse/version.hpp"

#include <iostream>
#include <string>

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

namespace {

void PrintUsage() {
  std::wcout << L"PulseService " << pulse::ServiceVersion().ToString().c_str() << L"\n"
             << L"Usage:\n"
             << L"  PulseService.exe --console         Run interactively\n"
             << L"  PulseService.exe --install         Install Windows service (admin)\n"
             << L"  PulseService.exe --install-start   Install, start, verify (admin)\n"
             << L"  PulseService.exe --start           Start installed service (admin)\n"
             << L"  PulseService.exe --stop            Stop installed service (admin)\n"
             << L"  PulseService.exe --restart         Restart installed service (admin)\n"
             << L"  PulseService.exe --status          Print SCM state (no admin)\n"
             << L"  PulseService.exe --uninstall       Remove Windows service (admin)\n"
             << L"  PulseService.exe --version\n"
             << L"  PulseService.exe                   Run as SCM service\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  for (int i = 1; i < argc; ++i) {
    const std::wstring arg = argv[i];
    if (arg == L"--help" || arg == L"-h") {
      PrintUsage();
      return 0;
    }
    if (arg == L"--version") {
      std::wcout << pulse::ServiceVersion().ToString().c_str() << L"\n";
      return 0;
    }
    if (arg == L"--console") {
      return pulse::RunConsoleMode(argc, argv);
    }
    if (arg == L"--install") {
      return pulse::InstallService();
    }
    if (arg == L"--install-start") {
      return pulse::InstallAndStartService();
    }
    if (arg == L"--start") {
      return pulse::StartInstalledService();
    }
    if (arg == L"--stop") {
      return pulse::StopInstalledService();
    }
    if (arg == L"--restart") {
      return pulse::RestartInstalledService();
    }
    if (arg == L"--status") {
      return pulse::PrintServiceStatus();
    }
    if (arg == L"--uninstall") {
      return pulse::UninstallService();
    }
  }
  return pulse::RunServiceMode();
}
