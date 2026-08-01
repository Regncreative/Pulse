# 29 — System Health Quality Milestone

Status: **In progress** (Phases 1–3 complete)

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
| **2 Network** | Overview polish + per-process ETW (ADR-009) | **Complete** |
| **3 Hardware** | Sensors Windows can expose (SMART, Storage temp IOCTLs, D3DKMT) | **Complete** |
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

## Phase 2 notes

- Health-only ETW session `PulseHealthNet` (not NT Kernel Logger); Timeline stays Event Log–only (ADR-007).
- Provider: `Microsoft-Windows-Kernel-Network`; light callback parse (no TDH); cumulative PID counters; sampler computes upload/download/total rates.
- On `StartTrace` / `EnableTraceEx2` failure under LocalService: leave `has_net_*` unset and log Win32 error — never fake rates.
- Flutter Network panel uses `ProcessInventoryList` (`ProcessListMetrics.network`, `ProcessGroupSort.networkDescending`).

## Phase 3 notes

Collector: `hardware_sensors_collector.*`, called from `HealthMetricsCollector::CollectHealthUpdate` after D3DKMT GPU telemetry (GPU fields are not duplicated).

### APIs used

| Metric | API | Notes |
|--------|-----|-------|
| SSD / NVMe temperature | `IOCTL_STORAGE_QUERY_PROPERTY` + `StorageDeviceTemperatureProperty` → `STORAGE_TEMPERATURE_DATA_DESCRIPTOR` / `STORAGE_TEMPERATURE_INFO` | Win10+; Celsius from sensor entries |
| NVMe SMART / health log | `IOCTL_STORAGE_QUERY_PROPERTY` + `StorageDeviceProtocolSpecificProperty` + `NVMeDataTypeLogPage` / `NVME_LOG_PAGE_HEALTH_INFO` | Microsoft NVMe pattern; Kelvin→°C; CriticalWarning; PowerOnHours; DataUnitRead/Written × 1000 × 512 |
| SMART predict failure | `IOCTL_STORAGE_PREDICT_FAILURE` → `STORAGE_PREDICT_FAILURE` | Fallback when NVMe CriticalWarning unavailable |
| GPU temp / fan / power % | Existing `SampleGpuD3dkmtTelemetry` (`KMTQAITYPE_ADAPTERPERFDATA`) | Unchanged; Hardware UI consumes `has_gpu_*` |
| CPU frequency | Existing collector frequency sample | Shown in Hardware panel |

### Intentional Not supported

| Metric | Reason |
|--------|--------|
| CPU package temperature | No reliable documented userspace package-temp API; `CallNtPowerInformation` thermal levels are not a stable public package sensor; ACPI thermal zones are fragile without WMI/vendor |
| CPU package power (W) | No documented Win32 package power without vendor MSR/WMI |
| CPU voltage | Same |
| GPU power (W) | D3DKMT `Power` is % scale only |
| GPU hotspot / VRAM junction | Vendor SDK only (NVAPI/ADL/IGCL — out of scope) |
| Motherboard temp / chassis fans / VRM | No documented Win32 path without vendor APIs |

Open `\\.\PhysicalDriveN` with `GENERIC_READ` + share read/write. Leave `has_*` false when IOCTL fails or values are out of range.

## Related

- [24 — Health metrics vs Task Manager](24-health-metrics-task-manager.md)
- [28 — App grouping](28-task-manager-app-grouping.md)
- [20 — ETW](20-etw-integration.md) (Health engine implemented; Timeline deferred)
- [ADR-009](decisions/ADR-009-health-network-etw.md)
