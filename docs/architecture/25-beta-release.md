# Pulse beta packaging

## Goal

Ship a portable first public beta without a full MSI yet.

## Produce a package

From a developer machine with Flutter + VS C++ Build Tools:

```powershell
.\tools\scripts\package_beta.ps1
```

Outputs:

| Path | Contents |
|------|----------|
| `dist/Pulse/` | `Pulse.exe` + Flutter assets + `service/PulseService.exe` |
| `dist/Pulse-0.1.0-beta-windows-x64.zip` | Zip of the folder |

## Fresh machine checklist

1. Extract zip to a folder the user can write (e.g. `%LOCALAPPDATA%\Pulse`)
2. Elevated: `service\install_service.ps1`
3. Confirm `Get-Service PulseService` is Running
4. Launch `Pulse.exe`
5. Complete or skip welcome
6. Timeline shows snapshot / live events
7. System Health shows live metrics
8. Diagnostics shows Connected
9. Stop service → UI shows offline empty states (no blank screens)
10. Start service → automatic reconnect

## Console mode (no SCM)

```powershell
.\service\PulseService.exe --console
.\Pulse.exe
```

## Known beta limits

- System Event Log channel only (Application / Security are future)
- Portable zip — not yet code-signed MSI/Inno
- Service runs as LocalService when installed via SCM
- `flutter build windows --release` may fail under non-ASCII paths (e.g. `OneDrive\Masaüstü`); `package_beta.ps1` stages to `C:\dev\Pulse-build` automatically
