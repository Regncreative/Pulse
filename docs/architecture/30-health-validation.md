# 30 — System Health validation methodology

Status: Phase 7 of the quality milestone ([29](29-system-health-quality-milestone.md))

## Principle

Compare Pulse to Windows Task Manager, Resource Monitor, Performance Monitor, and System Informer using the **same documented APIs** where possible. Never invent expected values. Acceptable delta: sample timing skew (~1 s) and rounding.

## Reference matrix

| Metric | Windows API (Pulse) | Compare with | Expected relationship |
|--------|---------------------|--------------|------------------------|
| CPU % (system) | PDH `% Processor Utility` | TM Performance | Within a few points |
| Process CPU | SPI ΔKernel+User / Δt / N | SI time-based; TM Details | Same family as SI time-based |
| Memory used/available | `GlobalMemoryStatusEx` | TM Performance Memory | Same formulas |
| Committed / pools | `GetPerformanceInfo` | TM / SI | Aligned |
| Cached / compression | PDH Memory counters | TM | Aligned when counters exist |
| GPU % / engines | PDH `\GPU Engine(*)` LUID-filtered | TM Performance GPU | Close; adapter selection may differ |
| GPU VRAM capacity | DXGI `GetDesc1` | TM / dxdiag | Aligned |
| GPU VRAM used | PDH `\GPU Adapter Memory(*)` | TM | Aligned when instances exist |
| GPU WDDM / PCI | D3DKMT QueryAdapterInfo | dxdiag | Aligned when D3DKMT succeeds |
| GPU temp/fan/power% | D3DKMT ADAPTERPERFDATA | Vendor panel | Only when non-zero; watts Not supported |
| Network adapter rates | `GetIfTable2` Δoctets | TM / RM | Close; adapter pick may differ |
| Per-process net | ETW `PulseHealthNet` | RM / SI | Rates only if session starts; else `—` |
| Disk throughput | PDH PhysicalDisk | TM | Aligned |
| SSD/NVMe temp / SMART | Storage IOCTL temperature + NVMe health log | CrystalDiskInfo-class tools | Aligned when IOCTL succeeds |
| CPU package temp | — | HWMonitor | **Not supported** (no public Win32) |

## Manual checklist

1. Start PulseService (installed LocalService) + Pulse Release.
2. Open System Health → CPU / Memory / GPU / Network / Disk / Hardware.
3. Open Task Manager Performance (same GPU/NIC/volume where possible).
4. Open Resource Monitor → Network / Memory.
5. Open Performance Monitor → add the same PDH counters Pulse documents.
6. Optionally System Informer for process private WS and time-based CPU.
7. Confirm Diagnostics shows service version, git commit, SHA256, ETW running or last error.
8. Timeline: filter Crash / Power / Service; confirm human titles and export JSON.

## Intentional differences

| Difference | Why |
|------------|-----|
| Process CPU ≠ TM Processes Utility | Pulse defaults to time-based SPI (SI-style); TM Performance uses Utility |
| Per-process net may be `—` | ETW session failed (logged); never ESTATS guesses |
| Resizable BAR / GPU watts | No reliable public boolean / watt API without vendor SDK |
| CPU package sensors | No public Win32 package-temp API |
| Security Timeline events | Often inaccessible under LocalService |

## Scripts

- `scripts/validate_memory_metrics.ps1` — Memory Win32/PDH dump matching Pulse formulas

## Phase status

Validation methodology documented. Live machine comparison remains an operator checklist before each beta.
