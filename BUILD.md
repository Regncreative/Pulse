# BUILD

## Prerequisites

- Windows 10 1809+ / Windows 11
- Visual Studio 2022+ or Build Tools with MSVC + CMake + Windows SDK
- Flutter stable (3.x) on `PATH` or `C:\Users\<you>\flutter\bin`
- Git

## Build PulseService

```powershell
# From a "x64 Native Tools" / VsDevCmd prompt:
cmake -S service/pulse_service -B build/service -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build/service
```

Outputs:

- `build/service/PulseService.exe`
- `build/service/pulse_wire_tests.exe`
- `build/service/pulse_ipc_ping.exe`

Run tests:

```powershell
.\build\service\pulse_wire_tests.exe
```

## Build Flutter app

```powershell
cd apps/pulse_app
flutter pub get
flutter build windows --debug
# or
flutter run -d windows
```

## Package beta (portable)

```powershell
.\tools\scripts\package_beta.ps1
```

Produces `dist\Pulse-Setup-0.3.1-beta-windows-x64.exe`, `dist\Pulse\`, and `dist\Pulse-0.3.1-beta-windows-x64.zip`. See [docs/architecture/25-beta-release.md](docs/architecture/25-beta-release.md).

## Install service (optional)

```powershell
# Elevated PowerShell
.\build\service\PulseService.exe --install
Start-Service PulseService
```

Uninstall:

```powershell
.\build\service\PulseService.exe --uninstall
```

Prefer `--console` during development.
