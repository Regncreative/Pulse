# R1 Product Stability — measurement notes

**Date:** 2026-08-01  
**Machine:** development workstation (not a clean VM)  
**Build under test:** running installed/dev Pulse UI + PulseService; service rebuilt with drop-oldest fix at `C:\dev\Pulse-service-build-r1` (not yet redeployed to SCM for these samples).

## Measured (honest)

| Metric | Target | Observed | Notes |
|--------|--------|----------|-------|
| Idle UI Working Set (`Pulse`) | &lt; 150 MB | **155.7 MB** | Over target by ~6 MB — do not “optimize blindly”; track in soak |
| PulseService Working Set | track | **25.2 MB** | SCM Running |
| PulseMCP | track | not running | Dev MCP not launched |
| Diagnostics ping smoke | SMOKE_OK | **SMOKE_OK** | `pulse_diagnostics_ping` against live pipe |
| Cold start UI | &lt; 1 s | **not measured this session** | Use stopwatch on next clean launch; record here |
| Warm start | informational | not measured | |
| Idle CPU | near zero | service CPU-seconds counter from process start only | Prefer Diagnostics % after 2 samples |
| FPS / frame time | ≥ 60 FPS | measure with Diagnostics open | Session sample not captured numerically here |
| IPC ping RTT | &lt; 50 ms | measure via Diagnostics → Ping | |

Snapshot artifact: `artifacts/perf/20260801-200300/` (local, gitignored).

## Validation status

| Procedure | Status |
|-----------|--------|
| Unit / widget tests | Pass (incl. advanced diagnostics + layout overflow) |
| Service `ctest` | Pass (4/4) on R1 rebuild |
| Overnight soak ≥8 h | **Pending maintainer** — `soak_overnight.ps1` |
| Clean-VM installer | **Pending maintainer** — doc 25 / 35 |
| Sleep/wake, monitor hot-plug, network | Documented in doc 35; spot-check on soak machine |

## Known limitations

- Collector latency and collector dropped-samples remain **Not supported** (no fabricated counters).
- Live queue **depth** is sum across clients; **capacity** is per client (labeled in UI).
- Performance mode `performance` vs `balanced` does not change refresh rates yet (subtitles honest).
- Theme redesign still out of roadmap scope / separate dirty tree.
- Redeploy R1 `PulseService.exe` to SCM before soak so drop-oldest is what you soak.
