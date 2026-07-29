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
             << L"  PulseService.exe --console     Run interactively\n"
             << L"  PulseService.exe --install     Install Windows service (admin)\n"
             << L"  PulseService.exe --uninstall   Remove Windows service (admin)\n"
             << L"  PulseService.exe --version\n"
             << L"  PulseService.exe               Run as SCM service\n";
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
    if (arg == L"--uninstall") {
      return pulse::UninstallService();
    }
  }
  return pulse::RunServiceMode();
}
