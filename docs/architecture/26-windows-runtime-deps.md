# Pulse Windows runtime dependencies (MSVC)

## Problem

Clean Windows 10/11 installs often **do not** include the Visual C++ 2015–2022 runtime.
Both binaries link against it:

| Binary | Required VC++ DLLs |
|--------|--------------------|
| `Pulse.exe` | `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll`, `MSVCP140.dll` (+ Universal CRT) |
| `PulseService.exe` | same |

Symptom on a clean PC:

```text
VCRUNTIME140_1.dll was not found
```

Universal CRT (`api-ms-win-crt-*` → `ucrtbase.dll`) ships with Windows 10/11 and is **not** the issue.

## Chosen deployment (beta)

Microsoft allows either:

1. **App-local** copy of redistributable CRT DLLs next to each EXE
2. **Central** install of `VC_redist.x64.exe` (admin; Windows Update can service later)

Pulse beta does **both** inside the **Inno Setup installer** (`Pulse-Setup-*-windows-x64.exe`):

| Step | Action |
|------|--------|
| Files | Install app + CRT DLLs under `%ProgramFiles%\Pulse` |
| Runtime | Quiet `redist\VC_redist.x64.exe` |
| Service | `PulseService.exe --install-start` (no PowerShell) |
| Launch | Start `Pulse.exe` |

End users never run `.ps1` scripts or change ExecutionPolicy.

## Verify packaging

```powershell
.\tools\scripts\verify_runtime_deps.ps1 -PackageDir dist\Pulse
```

Checks that required CRT DLLs sit next to both executables and that `dumpbin` dependents are covered.
