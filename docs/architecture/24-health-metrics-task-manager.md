# Health Metrics vs Windows Task Manager

Pulse System Health aims to stay within a few percentage points of Task Manager **Performance** under normal load, using official Win32 / PDH APIs only (read-only).

Source: `service/pulse_service/src/collectors/health_metrics_collector.cpp`  
Process CPU math: `service/pulse_service/src/collectors/process_metrics.cpp`  
Sample rate: ~1 Hz when a client enables health monitoring.

---

## Summary of alignment changes

| Metric | Pulse (current) | Task Manager Performance | Match quality |
|--------|-----------------|--------------------------|---------------|
| CPU % | `\Processor Information(_Total)\% Processor Utility`, clamped to 100 | Same counter family (utility), clamped | **Aligned** |
| Per-core CPU | `\Processor Information(*)\% Processor Utility` | Same family | **Aligned** |
| Memory in use | `TotalPhys − AvailPhys` (`GlobalMemoryStatusEx`) | Total − Available | **Aligned** |
| Memory available | `ullAvailPhys` | Available | **Aligned** |
| Committed | `GetPerformanceInfo` CommitTotal/Limit × PageSize | Commit / limit | **Aligned** |
| Cached | PDH Cache + Modified + Standby Reserve + Normal + Core/Code | Same composition (MSDN) | **Aligned** |
| Memory compression | PDH `\Memory\Compressed Bytes` | Memory compression | **Aligned** when counter exists |
| Hardware reserved | `GetPhysicallyInstalledSystemMemory − ullTotalPhys` | Hardware reserved | **Aligned** when installed API succeeds |
| Paged / Non-paged pool | `GetPerformanceInfo` KernelPaged/Nonpaged × PageSize | Paged / Non-paged pool | **Aligned** |
| Page faults/sec | PDH `\Memory\Page Faults/sec` | (optional) | **Aligned** when counter exists |
| GPU % | Max of `\GPU Engine(*)\Utilization Percentage` | Max engine util on selected GPU | **Close** |
| Disk R/W | `\PhysicalDisk(_Total)\Disk Read/Write Bytes/sec` | Same counters | **Aligned** |
| Disk capacity | Fixed volumes + present removable; primary prefers C: | Selected volume | **Aligned** (multi-volume) |
| Network | Single active non-virtual adapter octets / Δt | Selected adapter | **Close** |
| CPU speed | Base `~MHz` × `% Processor Performance` | Current / base clock | **Close** |
| Process memory | SPI **private** working set | Private WS | **Aligned** (with fallback) |
| Process identity | PID + CreateTime | SI process records | **Aligned** |

---

## Metric detail

### CPU (system %)

| | |
|--|--|
| **Pulse API** | PDH `\Processor Information(_Total)\% Processor Utility` |
| **Pulse calculation** | Formatted double; clamp to `[0, 100]` |
| **Fallback** | `GetSystemTimes` busy = `(Δkernel+Δuser−Δidle)/(Δkernel+Δuser)×100` |
| **Task Manager** | Performance tab uses **% Processor Utility** (can exceed 100% under turbo; UI clamps). Details tab still uses **% Processor Time**. |
| **Difference** | After alignment, Pulse matches Performance, not Details. Pre–24H2 Processes tab also used Utility; May 2025 updates moved Processes toward time-based industry formula — Pulse tracks **Performance**. |

### Per-core CPU

| | |
|--|--|
| **Pulse API** | `\Processor Information(*)\% Processor Utility` (fallback `\Processor(*)\% Processor Time`) |
| **Task Manager** | Logical processor graphs use the utility family on modern Windows |
| **Difference** | Instance naming (`0,0` vs `0`) handled by sorting instance names |

### Memory — In use / Available / Total

| | |
|--|--|
| **Pulse API** | `GlobalMemoryStatusEx` |
| **Pulse calculation** | used = `ullTotalPhys − ullAvailPhys` |
| **Task Manager** | Same Available definition (standby + free + zero); In use ≈ Total − Available |
| **Difference** | Typically within rounding / snapshot timing |

### Memory — Committed

| | |
|--|--|
| **Pulse API** | `GetPerformanceInfo` → `CommitTotal`, `CommitLimit` × `PageSize` |
| **Task Manager** | Commit charge / limit |
| **Difference** | Negligible |

### Memory — Cached

| | |
|--|--|
| **Pulse API** | PDH sum: Cache Bytes + Modified Page List Bytes + Standby Cache Reserve + Normal Priority + Core/Code Bytes |
| **Fallback** | `PERFORMANCE_INFORMATION.SystemCache × PageSize` |
| **Task Manager** | Same PDH composition ([Memory Performance Information](https://learn.microsoft.com/en-us/windows/win32/memory/memory-performance-information)) |
| **Difference** | Small timing skew; Core vs Code counter name varies by Windows build |

### Memory — Compression

| | |
|--|--|
| **Pulse API** | PDH `\Memory\Compressed Bytes` |
| **Task Manager** | Memory compression |
| **Difference** | If the counter is missing on a build, Pulse shows `—` (never estimated) |

### Memory — Hardware reserved

| | |
|--|--|
| **Pulse API** | `GetPhysicallyInstalledSystemMemory` (KB→bytes) − `MEMORYSTATUSEX.ullTotalPhys` |
| **Task Manager** | Hardware reserved |
| **Difference** | Shown only when installed ≥ usable; otherwise `—` |

### Memory — Paged / Non-paged pool

| | |
|--|--|
| **Pulse API** | `GetPerformanceInfo` → `KernelPaged` / `KernelNonpaged` × `PageSize` |
| **Task Manager** | Paged pool / Non-paged pool |
| **Difference** | Negligible snapshot skew |

### Memory — Page Faults/sec (optional)

| | |
|--|--|
| **Pulse API** | PDH `\Memory\Page Faults/sec` |
| **Task Manager** | Not always on Performance > Memory summary; Resource Monitor shows faults |
| **Difference** | Rate counters need a primed PDH sample; first tick may be `—` |

### Memory panel UI (presentation)

| | |
|--|--|
| **Process list** | Same inventory + app grouping as CPU ([28-task-manager-app-grouping.md](28-task-manager-app-grouping.md)) |
| **Memory value** | SPI `WorkingSetPrivateSize` (`HealthProcessEntry.memory_bytes`); never shared WS for the column |
| **Sort** | App groups by **sum of private WS** descending within each section |
| **Formatting** | `< 1024 MB` → MB; `≥ 1024 MB` → `X.XX GB` (`formatMemorySize`) |
| **Selection** | Application totals: private WS, commit (`PagefileUsage`), shared ≈ `WorkingSetSize − Private`, paged/non-paged quotas, then each child PID |
| **Extra SPI fields** | `working_set_bytes`, `commit_bytes`, `paged_pool_bytes`, `nonpaged_pool_bytes` on inventory entries |
| **Polling** | No extra poll — reuses health inventory deltas (~1 Hz) |

### Shared working set note

SPI exposes `WorkingSetSize` and `WorkingSetPrivateSize` but not a dedicated “Shared” field. Pulse displays:

`shared ≈ WorkingSetSize − WorkingSetPrivateSize`

This matches the usual Task Manager Details relationship without `OpenProcess` / `QueryWorkingSetEx`. Exact shareable pages (SI “Shareable”) may differ slightly.

### GPU %

| | |
|--|--|
| **Pulse API** | PDH `\GPU Engine(*)\Utilization Percentage`, filtered to selected adapter LUID; overall = max engine |
| **Per-engine** | Max util for `engtype_3D` / `Compute` / `Copy` / `VideoDecode` / `VideoEncode` on that LUID |
| **Task Manager** | Same PDH family for Performance → GPU graphs |
| **Difference** | Pulse prefers discrete DXGI adapter; TM uses the user-selected GPU |

### GPU identity / VRAM / adapter

| | |
|--|--|
| **Name / Vendor / LUID / capacity** | DXGI `EnumAdapters1` + `GetDesc1` (`gpu_adapter_info.cpp`) |
| **Driver version / date** | Display class registry (`{4d36e968-…}`) matched by description |
| **Hardware scheduling** | `HKLM\…\GraphicsDrivers\HwSchMode` (2 = on) |
| **DirectX** | Max D3D12 feature level via `D3D12CreateDevice(..., nullptr)` probe |
| **Dedicated / Shared usage** | PDH `\GPU Adapter Memory(*)\Dedicated Usage` / `Shared Usage` (LUID-filtered) |
| **WDDM version** | `D3DKMTOpenAdapterFromLuid` + `D3DKMTQueryAdapterInfo(KMTQAITYPE_DRIVERVERSION)` via `gdi32` / `d3dkmthk.h` (Windows SDK) |
| **PCI location** | `KMTQAITYPE_ADAPTERADDRESS` → `PCI bus:device.function` |
| **PCIe link speed / width** | SetupAPI `DEVPKEY_PciDevice_CurrentLinkSpeed` / `CurrentLinkWidth` when the display device matches DXGI description |
| **Clocks / fan / temp / power %** | `KMTQAITYPE_ADAPTERPERFDATA` + `NODEPERFDATA` — only when the driver returns non-zero values; else `—` / Not supported |
| **Resizable BAR** | Not supported (no reliable public userspace bool; Microsoft documents BAR resize as mostly invisible to clients) |
| **Power (W)** | Not supported; D3DKMT `Power` is tenths of a percentage, not watts. Absolute watts need vendor SDK |

### GPU processes

| | |
|--|--|
| **API** | PDH `\GPU Engine(*)\Utilization Percentage` + `\GPU Process Memory(*)\Dedicated/Shared Usage`, LUID-filtered; merged into process inventory by PID |
| **UI** | Same inventory + app grouping as CPU/Memory (`ProcessInventoryList` + `ProcessGroupSort.gpuDescending`) |
| **Columns** | Name, GPU %, Dedicated, Shared |
| **Icons** | Flutter `ProcessAppIcon` from executable path |
| **Engines** | 3D / Compute / Copy / Encode / Decode / Video Processing (PDH `engtype_*`) |

### Network (system adapter)

| | |
|--|--|
| **Selection** | `GetIfTable2` busiest up non-virtual NIC |
| **Identity** | `GetAdaptersAddresses` + Net class registry (MAC, MTU, DHCP, leases, description) |
| **Rates** | Δ In/Out octets / Δt; peak/avg since monitoring start; util % vs link speed |
| **Counters** | `GetIfEntry2` bytes/packets/errors/discards |
| **Wi‑Fi** | Native WLAN (`wlanapi`) SSID / signal / channel / security when IEEE80211 |
| **Per-process** | **ETW** `NetworkEtwEngine` (`PulseHealthNet` + Microsoft-Windows-Kernel-Network) — upload/download/total when session starts; else `—` |

### CPU / Memory / Disk overview enrichment

| Area | Source | Notes |
|------|--------|-------|
| CPU topology / caches / ISA | `GetLogicalProcessorInformationEx`, `IsProcessorFeaturePresent`, CPUID hypervisor leaf | Voltage / TDP / package power → `—` |
| Memory modules | SMBIOS Type 17 via `GetSystemFirmwareTable('RSMB')` | Channels often unset |
| Disk identity | `\\.\PhysicalDrive0` Storage IOCTLs | Model/serial/bus/TRIM/geometry |
| Disk temperature | `StorageDeviceTemperatureProperty` (+ NVMe health log fallback) | `has_ssd_temp_c` when IOCTL succeeds |
| Disk SMART / POH / lifetime I/O | NVMe `NVME_LOG_PAGE_HEALTH_INFO` + `IOCTL_STORAGE_PREDICT_FAILURE` | `has_disk_smart_ok`, `has_disk_power_on_hours`, `has_disk_total_bytes_*` |

Code: `service/pulse_service/src/collectors/gpu_adapter_info.*`, `system_overview_info.*`, `health_metrics_collector.cpp`.

### GPU VRAM

| | |
|--|--|
| **Capacity** | DXGI `DedicatedVideoMemory` / `SharedSystemMemory` |
| **Usage** | PDH Adapter Memory Dedicated/Shared Usage when counters exist |
| **Difference** | Without PDH instances, usage stays `—` (never invent). Absolute board power watts need vendor SDK. |

### Disk throughput

| | |
|--|--|
| **Pulse API** | `\PhysicalDisk(_Total)\Disk Read/Write Bytes/sec` |
| **Task Manager** | Same PhysicalDisk counters for throughput |
| **Difference** | TM also shows **Active time %** (`100 − % Idle Time`). Pulse does not expose active time yet. |

### Disk capacity

| | |
|--|--|
| **Pulse API** | `GetLogicalDriveStringsW` + `GetDiskFreeSpaceExW` per volume |
| **Policy** | Fixed volumes always listed with capacity. Removable/optical listed when media present. Network volumes listed by letter only — no `GetVolumeInformationW` / `GetDiskFreeSpaceExW` (avoids SMB hangs). |
| **Primary summary** | Prefers `C:`, else first fixed volume → `disk_used_bytes` / `disk_total_bytes` |
| **Task Manager** | Per selected volume |
| **Difference** | Pulse shows **all** relevant volumes; TM focuses on the selected one |

### Physical disk throughput (per disk)

| | |
|--|--|
| **Pulse API** | `\PhysicalDisk(*)\Disk Read/Write Bytes/sec` (excludes `_Total` for the list; `_Total` kept for aggregate sparklines) |
| **Task Manager** | Per selected physical disk |
| **Difference** | Pulse lists all instances; aggregate R/W still drives the main sparkline |

### Top processes (GPU / Disk side panels)

| | |
|--|--|
| **Pulse API** | `NtQuerySystemInformation(SystemProcessInformation)` via `ntdll` |
| **Pulse fields** | Name, PID, CPU %, **private** working set (fallback shared WS), Thread/Handle counts |
| **Task Manager** | Same system-process snapshot family (no per-process `OpenProcess`) |
| **Difference** | Side panels still show **top-N** lists. **CPU and Memory** panels use the full inventory + app groups. |

### Validation methodology (Memory)

1. Run `scripts/validate_memory_metrics.ps1` — prints the same Win32/PDH formulas Pulse uses.
2. Open Task Manager → Performance → Memory and Resource Monitor → Memory at the same moment.
3. Compare Overview rows (Used/Total, Available, Committed, Cached, Compression, Hardware Reserved, pools).
4. For a known PID: compare Pulse child Private WS to TM Details **Memory (private working set)** / System Informer Private Bytes / Working Set Private.
5. For an app group: sum private WS of children; Pulse collapsed row must equal that sum (not the first child’s value).

Acceptable delta: sub-second sample skew (± a few MB). Any systematic gap means wrong API or formula — fix, do not average.

### CPU process inventory (Processes tab–style)

| | |
|--|--|
| **Identity** | **(PID + CreateTime)** for CPU / Disk / Net baselines and inventory merge. PID recycle resets metrics (System Informer process-record model). |
| **Pulse API** | Full SPI walk each sample; delta push (~1 Hz, full resync ~30 s) |
| **CPU (default)** | **Time-based:** Δ(Kernel+User) / Δt / N_logical × 100, clamped. Same family as System Informer time-based / classic TM Details. |
| **CPU (optional)** | **Cycle-based:** ΔCycleTime / (Σ process ΔCycle + Σ idle ΔCycle) × 100. Implemented in `ProcessCpuCalculator`; default remains time-based (`SetProcessCpuMode`). |
| **Memory** | Prefer SPI `WorkingSetPrivateSize`; fall back to `WorkingSetSize` if private is zero. |
| **Disk** | Δ(Read+Write+Other TransferCount) / Δt (SI IoCounters-style). Impossible rates rejected. |
| **Network** | Deferred — no ESTATS. Missing → `—`. Future ETW. |
| **Sections** | Apps = EnumWindows; Windows = critical/SystemRoot heuristics; else Background. |
| **Difference vs TM** | No UWP app tree. Stable name order. Process CPU is time-based by default (not Performance Utility). Net often incomplete under LocalService. |

### Process CPU calculation modes

| Mode | Formula | Notes |
|------|---------|-------|
| TimeBased (default) | Δ Kernel+User / Δt / logical × 100 | Classic TM Details / SI time-based |
| CycleBased | Δ process cycles / (Σ process + idle cycle Δ) × 100 | SI cycle-based effort model |

Code: `service/pulse_service/src/collectors/process_metrics.{hpp,cpp}`.

### Network (system adapter)

| | |
|--|--|
| **Pulse API** | `GetIfTable2` + `GetAdaptersAddresses` + `GetIfEntry2` + WLANAPI |
| **Pulse calculation** | Δoctets / Δseconds; session peak/avg; util vs TransmitLinkSpeed |
| **Difference** | Adapter selection can diverge from TM user selection; Wi‑Fi fields only when connected wireless |

See expanded Network section above for static identity fields.

### Per-process metrics

| Metric | Pulse | TM / System Informer | Remaining gap |
|--------|-------|----------------------|---------------|
| CPU | Time-based SPI (default); cycle optional | SI cycle default; TM may use Utility | Default ≠ Utility |
| Memory | **Private** WS from SPI | Private WS | Aligned when private ≠ 0 |
| Disk | Read+Write+Other / Δt | IoCounters-style | Not exclusive physical disk |
| Network | **ETW** Kernel-Network send/recv (ADR-009) | TM / SI use **ETW** kernel TCP/UDP | Rates unset if session fails |
| Lifetime | PID + CreateTime | SI CreateTime records | Aligned |

### Per-process network — API decision (ESTATS removed)

Runtime investigation (2026-08) proved `GetPerTcpConnectionEStats` is **not** a correct source for Pulse:

| Approach | PID attribution | Needs elevation | Works as LocalService | Robustness | Used by |
|----------|-----------------|-----------------|----------------------|------------|---------|
| **ESTATS** (`GetPerTcpConnectionEStats`) | Per TCP row → PID | Yes (admin); enable via `SetPerTcpConnectionEStats` | No — undefined ROD without enable; garbage multi‑GB/s rates observed | Poor | Niche tools only |
| **IP Helper tables** (`GetExtendedTcpTable`) | Connection owners only | Limited | Yes for table; **no byte counters** | Good for sockets list | Connection viewers |
| **PDH / Perf Counters** | Process(*) has no Network Bytes | N/A | N/A | **Cannot** do per-process net | System adapter only |
| **ETW** kernel `TcpIp`/`UdpIp` (NetworkTCPIP) | Event PID + size | Typically admin / privileged session | Needs design (service account + session) | **Best** — what TM / Resource Monitor / System Informer use | Mature monitors |

**Recommendation:** Do **not** filter ESTATS garbage. Use the **ETW** Network Engine ([20-etw-integration.md](20-etw-integration.md), [ADR-009](decisions/ADR-009-health-network-etw.md)). Keep system-adapter rates via `GetIfTable2`. Leave per-process `has_net_*` unset when the session cannot start.

### Process network via ETW (Phase 2)

Real-time Pulse-owned session `PulseHealthNet` on `Microsoft-Windows-Kernel-Network` send/recv events; aggregate cumulative bytes by PID; publish rates on `HealthProcessEntry` (`net_bps`, `net_upload_bps`, `net_download_bps`, `net_bytes_total`). Privilege model stays explicit — never bypass Windows security. Timeline remains Event Log–only.

### Temperatures & hardware sensors (Phase 3)

| Sensor | Source | UI when unavailable |
|--------|--------|---------------------|
| GPU temp / fan / power % | D3DKMT `ADAPTERPERFDATA` | Not supported |
| SSD / NVMe temp | `IOCTL_STORAGE_QUERY_PROPERTY` `StorageDeviceTemperatureProperty`; else NVMe SMART log Kelvin | Not supported |
| Disk SMART health | NVMe CriticalWarning == 0, else `IOCTL_STORAGE_PREDICT_FAILURE` | Not supported |
| Power-on hours / lifetime R/W | NVMe SMART health log (`PowerOnHours`, `DataUnitRead`/`Written`) | Not supported |
| CPU package temp / power / voltage | — | Not supported (no public package sensor without vendor/WMI) |
| Motherboard / chassis fans | — | Not supported |

Code: `service/pulse_service/src/collectors/hardware_sensors_collector.*`.

---

## Intentional non-goals

- Matching TM **Performance** Utility on every **process** row
- Absolute GPU power **watts** / Resizable BAR without a documented userspace detection API or vendor SDK
- CPU package temperature / motherboard sensors via undocumented or vendor-only APIs (NVAPI / ADL / Intel IGCL / WMI heuristics)
- Exact adapter / GPU picker parity with Task Manager UI selection
- Network drive capacity every second
- TM App tree / UWP grouping beyond Phase A ([28-task-manager-app-grouping.md](28-task-manager-app-grouping.md))
- Per-process net without a working ETW session (leave unset — never invent)
- NVAPI / ADL / Intel IGCL for board sensors beyond what D3DKMT exposes

## Verification

Compare Pulse with **Task Manager** and **System Informer** (~30 s idle + light load):

| Check | Expectation |
|-------|-------------|
| System cards | Within a few points of TM Performance (same adapter/volume) |
| Memory Overview | Same Win32/PDH formulas as `scripts/validate_memory_metrics.ps1` |
| Process Memory | Near TM/SI private WS; groups = sum of private WS |
| Process CPU | Track SI time-based; may diverge from TM Processes Utility |
| Process Disk | Same order of magnitude as SI I/O |
| Process Network | Match order of magnitude with SI/TM when `PulseHealthNet` is up; `—` if ETW start failed |
| PID recycle | Relaunch same image: metrics reset (no stuck baseline) |
| Inventory UI | CPU: stable name order; Memory: private-WS sort within sections |

### Example host snapshot (validation script, same APIs as Pulse)

| Metric | Windows API | Example raw read |
|--------|-------------|------------------|
| Total Physical | `GlobalMemoryStatusEx.ullTotalPhys` | usable RAM |
| Used | `TotalPhys − AvailPhys` | In use |
| Available | `ullAvailPhys` | Available |
| Committed / Limit | `GetPerformanceInfo` × PageSize | Commit |
| Cached | PDH Cache+Modified+Standby* (fallback SystemCache) | Cached |
| Compression | PDH `\Memory\Compressed Bytes` | or `—` |
| Hardware Reserved | Installed − TotalPhys | or `—` |
| Paged / Non-paged | KernelPaged/Nonpaged × PageSize | pools |
| Page Faults/sec | PDH `\Memory\Page Faults/sec` | optional |

Difference vs Task Manager should be timing/rounding only. Systematic gaps → wrong counter, not UI polish.
