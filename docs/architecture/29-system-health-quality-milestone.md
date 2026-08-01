# 29 — System Health Quality Milestone

Status: **In progress** (Phase 1 complete)

## Goal

Bring every System Health surface to the same quality bar as CPU and Memory:

- Windows-native APIs only
- No fabricated metrics (`has_* = false` → `—` / Not supported)
- Collector → IPC → Flutter unchanged
- Phased delivery with a commit per phase

## Phases

| Phase | Scope | Status |
|-------|--------|--------|
| **1 GPU** | WDDM/PCI/engines/VRAM/process inventory grouping + D3DKMT telemetry when non-zero | **Complete** |
| **2 Network** | Overview polish + per-process ETW (ADR superseding ADR-007 for health net) | Pending |
| **3 Hardware** | Sensors Windows can expose (SMART, ACPI, D3DKMT, documented IOCTLs) | Pending |
| **4 Timeline** | Event-type depth (crash/BSOD/update/device/power) via Event Log channels + intelligence | Pending |
| **5 Diagnostics** | Service/IPC/collector/Flutter instrumentation | Pending |
| **6 UX** | Polish overflow, empty states, virtualization, a11y | Pending |
| **7 Validation** | Compare vs Task Manager / Resource Monitor / PerfMon / System Informer | Pending |
| **8 Docs + beta** | ADRs, release notes, package `0.1.3-beta` | Pending |

## Phase 1 notes

- D3DKMT is used via Windows SDK `d3dkmthk.h` + `gdi32` (Microsoft-documented), not a vendor SDK.
- Resizable BAR remains Not supported — no reliable public userspace boolean.
- Absolute GPU watts remain Not supported (D3DKMT power is % scale).
- Per-process GPU util/VRAM come from PDH and merge into the SPI inventory.

## Related

- [24 — Health metrics vs Task Manager](24-health-metrics-task-manager.md)
- [28 — App grouping](28-task-manager-app-grouping.md)
- [20 — ETW](20-etw-integration.md) (Phase 2)
