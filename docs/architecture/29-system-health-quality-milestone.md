# 29 — System Health Quality Milestone

Status: **Complete** (Phases 1–8; shipping as `0.1.3-beta`)

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
| **4 Timeline** | Event-type depth (crash/BSOD/update/device/power) via Event Log channels + intelligence | **Complete** |
| **5 Diagnostics** | Service/IPC/collector/Flutter instrumentation | **Complete** |
| **6 UX** | Polish overflow, empty states, virtualization, a11y | **Complete** |
| **7 Validation** | Compare vs Task Manager / Resource Monitor / PerfMon / System Informer | **Complete** (methodology: [30](30-health-validation.md)) |
| **8 Docs + beta** | ADRs, release notes, package `0.1.3-beta` | **Complete** |

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

## Phase 4 notes

Timeline remains **Windows Event Log only** (Wevtapi) — no ETW Timeline ingest (ADR-007).

### Channels attempted

| Channel | Behavior |
|---------|----------|
| System | Required attempt |
| Application | Optional |
| Setup | Optional |
| Microsoft-Windows-WindowsUpdateClient/Operational | Optional |
| Microsoft-Windows-Kernel-PnP/Configuration | Optional |
| Microsoft-Windows-Kernel-Power/Thermal-Operational | Optional (events may appear; thermal-specific humanizer rules omitted unless documented) |
| Microsoft-Windows-Kernel-Boot/Operational | Optional |
| Security | `EvtOpenLog` probe first — **often inaccessible under LocalService**; skip + log |

Snapshots merge newest-first with a fair per-channel budget and IPC limit ≤500. Live monitoring starts one `EvtSubscribe` per accessible channel.

### Intelligence / humanizer

Documented Event IDs only (Kernel-Power 41/42/107, EventLog 6008, WER/BugCheck 1001, Application Error 1000 / Hang 1002, SCM 7023/7031/7034/7036/7040/7045, WindowsUpdateClient 19/20/43/44, Kernel-PnP 400/410/411, Security 4624/4634, disk 7/51, plus existing COM/network/boot/time rules).

### Flutter

Timeline filters: severity, source (System / Application / Security / Other), type/category chips (Crash, Service, Power, Update, Device, Boot, Security, Storage). Empty states when filters match nothing. Live stream unchanged.

## Phase 5 notes

Diagnostics surfaces **real** service, IPC, collector, and Flutter client metrics only. Missing data shows `—` / Not supported — never invent.

### Service identity (`DiagnosticsSnapshot` fields 33–41)

| Field | Source |
|-------|--------|
| `executable_path` | `GetModuleFileNameW` |
| `build_version` | `VersionInfo` / `ServiceVersion().ToString()` |
| `git_commit` | CMake configure → `pulse_build_info.hpp` (`git rev-parse --short HEAD`, or `-DPULSE_GIT_COMMIT=…`, else `unknown`) |
| `binary_sha256` | BCrypt SHA-256 of running `PulseService.exe`, cached once at first request |
| `install_path` | SCM `QueryServiceConfig` ImagePath exe |
| `paths_match` | Normalized case-insensitive compare (only when both paths exist) |
| `scm_state` / `scm_startup_type` | SCM `QueryServiceStatusEx` + `QueryServiceConfig` |

### IPC (fields 42–47 + client)

| Metric | Source |
|--------|--------|
| Protocol version | Existing `kProtocolVersion` on snapshot |
| Message / byte counters | Service frame I/O (`ipc_messages_*`, `ipc_bytes_*`) |
| Messages/sec, bytes/sec | Delta over wall time between Diagnostics polls (`has_*` after second sample) |
| Ping / snapshot latency | Flutter client wall-clock RTT (`IpcStatus` + Diagnostics RPC) — not inventable on the service without clock sync |
| Reconnect history | Flutter ring of last N reconnect timestamps/reasons |

### Collectors (fields 48–51)

| Metric | Source |
|--------|--------|
| Health sample rate | Documented ~1 Hz when a client has health monitoring enabled; `0` when idle |
| Network ETW running + last_error | `NetworkEtwEngine` (ADR-009) |
| Dropped samples | **Not supported** — no counter instrumented |

### Flutter client (UI-only)

| Metric | Source |
|--------|--------|
| FPS / build / raster / frame time | `SchedulerBinding` `FrameTiming` callbacks |
| Memory (RSS) | `ProcessInfo.currentRss` (WorkingSet on Windows) |
| Rebuild notes | Light counter on Diagnostics entry |

### Event pipeline

Per-stage status + detail strings (`stage_*_detail`) from live subscribe / queue pressure / intelligence in-process. No fabricated stage timings.

### Intentional Not supported (Phase 5 / R1)

| Metric | Reason |
|--------|--------|
| Collector dropped samples | No drop counter exists on health/ETW collectors |
| Collector latency histogram | Not instrumented |
| Service-side ping RTT in snapshot | Requires synchronized clocks; client measures RTT instead |
| Structured collector log tail | Skipped (heavy); export zip already includes recent app logs |

Live **queue overflow** is instrumented as `live_events_dropped` (drop **oldest** per connection — ADR-008 / doc 05). See [35-product-stability.md](35-product-stability.md).

## Related

- [24 — Health metrics vs Task Manager](24-health-metrics-task-manager.md)
- [28 — App grouping](28-task-manager-app-grouping.md)
- [20 — ETW](20-etw-integration.md) (Health engine implemented; Timeline deferred)
- [ADR-009](decisions/ADR-009-health-network-etw.md)
- [05 — IPC](05-ipc.md)
- [04 — Native service](04-native-service.md)
