# Health Metrics vs Windows Task Manager

Pulse System Health aims to stay within a few percentage points of Task Manager **Performance** under normal load, using official Win32 / PDH APIs only (read-only).

Source: `service/pulse_service/src/collectors/health_metrics_collector.cpp`  
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
| GPU % | Max of `\GPU Engine(*)\Utilization Percentage` | Max engine util on selected GPU | **Close** |
| Disk R/W | `\PhysicalDisk(_Total)\Disk Read/Write Bytes/sec` | Same counters | **Aligned** |
| Disk capacity | `GetDiskFreeSpaceExW(C:)` | Selected volume (often C:) | **Close** (C: only) |
| Network | Single active non-virtual adapter octets / Δt | Selected adapter | **Close** |
| CPU speed | Base `~MHz` × `% Processor Performance` | Current / base clock | **Close** |

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

### GPU %

| | |
|--|--|
| **Pulse API** | `\GPU Engine(*)\Utilization Percentage`, **max** across instances |
| **Task Manager** | Overall GPU ≈ highest engine util for the selected adapter |
| **Difference** | Pulse does not multi-select GPUs; DXGI adapter 0 is used for **identity/VRAM capacity** only. Multi-GPU systems may differ if TM selects a different adapter. |

### GPU VRAM

| | |
|--|--|
| **Pulse API** | DXGI `DedicatedVideoMemory` / `SharedSystemMemory` (capacity) |
| **Task Manager** | Shows dedicated/shared usage and capacity |
| **Difference** | **Cannot match usage** without vendor APIs (NVAPI/ADL) or undocumented counters. Pulse shows **capacity only**. |

### Disk throughput

| | |
|--|--|
| **Pulse API** | `\PhysicalDisk(_Total)\Disk Read/Write Bytes/sec` |
| **Task Manager** | Same PhysicalDisk counters for throughput |
| **Difference** | TM also shows **Active time %** (`100 − % Idle Time`). Pulse does not expose active time yet. |

### Disk capacity

| | |
|--|--|
| **Pulse API** | `GetDiskFreeSpaceExW(L"C:\\")` |
| **Task Manager** | Per selected volume |
| **Difference** | Pulse is **C: only** |

### Network

| | |
|--|--|
| **Pulse API** | `GetIfTable2` on one active up adapter (prefer non-virtual, highest cumulative traffic) |
| **Pulse calculation** | `Δoctets / Δseconds` |
| **Task Manager** | Throughput for the **user-selected** adapter |
| **Difference** | Adapter selection can diverge. Pulse no longer sums all NICs (that over-reported vs TM). |

### Per-process tops

| Metric | Pulse | Task Manager | Limitation |
|--------|-------|--------------|------------|
| Process CPU | `GetProcessTimes` / elapsed / logical CPUs | Processes/Details formulas vary by Windows build | May differ from Processes tab Utility era |
| Process Memory | Working set (`GetProcessMemoryInfo`) | Often **private** working set | Shared WS causes higher Pulse values |
| Process GPU | Max GPU engine util for PID | Similar | Engine coverage depends on PDH instances |
| Process Disk | All process I/O bytes / Δt | Disk column is I/O-ish | Not physical-disk exclusive |
| Process Network | IPv4 TCP ESTATS only | Broader | **No UDP/IPv6** |

### Temperatures

| | |
|--|--|
| **Pulse** | Not collected (never fabricated) |
| **Task Manager** | Not shown on Performance for CPU/GPU on all SKUs; OEM tools use WMI/vendor |
| **Limitation** | No stable public Win32 API for CPU/GPU package temp |

---

## Intentional non-goals

- Matching Task Manager **Details** tab CPU (% Processor Time) when Performance uses Utility
- Live VRAM **usage** without vendor SDKs
- Multi-volume disk inventory
- Exact adapter parity without a UI adapter picker
- Temperatures

## Verification

Compare Pulse System Health with Task Manager Performance side-by-side for ~30 s under idle and light load. Expect CPU / Memory / Disk / Network within a few points when the same adapter/volume is in view.
