# Pulse beta packaging

## Goal

Ship a **normal Windows installer** so a clean PC reaches Connected without PowerShell.

## Primary deliverable

`dist/Pulse-Setup-0.2.0-beta-windows-x64.exe` (Inno Setup)

The installer (admin / UAC):

1. Copies Pulse into `Program Files\Pulse`
2. Quietly installs `VC_redist.x64.exe` when present
3. Runs `PulseService.exe --install-start` (register auto-start service + start + verify)
4. Offers to launch `Pulse.exe`

No `.ps1`. No ExecutionPolicy. No manual service steps.

## Produce a package

Prerequisites: Flutter, VS C++ Build Tools, [Inno Setup 6](https://jrsoftware.org/isinfo.php) (`winget install JRSoftware.InnoSetup`).

```powershell
.\tools\scripts\package_beta.ps1
```

| Output | Role |
|--------|------|
| `dist/Pulse-Setup-0.2.0-beta-windows-x64.exe` | **End-user installer** |
| `dist/Pulse/` | Payload used by Inno |
| `dist/Pulse-0.2.0-beta-windows-x64.zip` | Optional payload archive |

## Fresh machine checklist

1. Copy **only** the Setup `.exe` to a clean Windows 10/11 PC
2. Double-click Setup → UAC Yes
3. Finish wizard (Launch Pulse checked)
4. Confirm tray/status shows Connected / Live within a few seconds
5. If Offline: use in-app **Start PulseService** / **Repair / Install** (UAC) — do not require Services.msc
6. Timeline and System Health populate (multi-channel Timeline — see below)
7. Reboot → PulseService still Running (auto-start) → Pulse reconnects
8. Open **Diagnostics** → confirm Performance budgets card; optional: enable advanced diagnostics
9. Record cold-start / idle RSS in [r1-stability-measurements.md](r1-stability-measurements.md) when validating an R1 train

Full stability procedures: [35-product-stability.md](35-product-stability.md).

## Service CLI (developers)

```text
PulseService.exe --install-start   Elevate: install/update auto-start + start + wait RUNNING
PulseService.exe --uninstall       Elevate: stop + delete service
PulseService.exe --console         Dev foreground mode (no SCM)
```

## Runtime dependencies

See [26-windows-runtime-deps.md](26-windows-runtime-deps.md).

## Timeline channels (current)

Timeline uses the **diagnostics multi-channel set** (not System-only). Clients that still send `channel=System` receive that multi-channel diagnostics snapshot; see [21-event-viewer-integration.md](21-event-viewer-integration.md) and [07-timeline-engine.md](07-timeline-engine.md).

## Known beta limits

- Not code-signed yet (SmartScreen may warn)
- `flutter build windows --release` may need ASCII staging path (`package_beta.ps1` handles this)
- PulseMCP M1 is present in-repo; installer packaging of `PulseMCP.exe` is roadmap R6
- Inventory beyond processes is not shipped (roadmap R3)
