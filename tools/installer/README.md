# Pulse Windows installer

End-user deliverable is built with **Inno Setup 6**:

```text
tools/installer/Pulse.iss  →  dist/Pulse-Setup-0.3.1-beta-windows-x64.exe
```

## Behavior

1. UAC elevation (`PrivilegesRequired=admin`)
2. Install files under `%ProgramFiles%\Pulse`
3. Quiet `VC_redist.x64.exe` when present
4. `PulseService.exe --install-start` (SCM register + start + verify RUNNING)
5. Launch `Pulse.exe`

No PowerShell scripts are required for installation.

## Build

```powershell
.\tools\scripts\package_beta.ps1
```

Requires `ISCC.exe` (Inno Setup 6).
