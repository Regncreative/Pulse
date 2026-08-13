# Pulse release packaging

## Goal

Ship a **normal Windows installer** so a clean PC reaches Connected without PowerShell.

## Primary deliverable

`dist/Pulse-Setup-1.1.0-windows-x64.exe` (Inno Setup)

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
| `dist/Pulse-Setup-1.1.0-windows-x64.exe` | **End-user installer** |
| `dist/Pulse/` | Payload used by Inno |
| `dist/Pulse-1.1.0-windows-x64.zip` | Optional payload archive (**not** a true portable SKU — see [40](40-portable-vs-service.md)) |

## Fresh machine checklist

1. Copy **only** the Setup `.exe` to a clean Windows 10/11 PC
2. Double-click Setup → UAC Yes
3. Finish wizard (Launch Pulse checked)
4. Confirm status shows Connected / Live within a few seconds
5. If Offline: use in-app **Start PulseService** / **Repair / Install** (UAC) — do not require Services.msc
6. Timeline, System Health, Inventory, and Reports populate as expected
7. Reboot → PulseService still Running (auto-start) → Pulse reconnects
8. Optional: **Settings → AI Integration** for PulseMCP
9. Open **Diagnostics** → confirm service version **1.1.0**

Full stability procedures: [35-product-stability.md](35-product-stability.md). Release notes: [v1.1.0.md](../releases/v1.1.0.md).

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

## Known limits (stable)

- Not code-signed yet (SmartScreen may warn)
- `flutter build windows --release` may need ASCII staging path (`package_beta.ps1` handles this)
- Pulse is distributed via **GitHub Releases**, not the Microsoft Store
- ZIP payload is not a true portable SKU ([40](40-portable-vs-service.md))
