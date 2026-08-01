# 35 — Product Stability (R1)

**Status:** Active (Wave A / R1)  
**Roadmap:** [34-engineering-roadmap.md](34-engineering-roadmap.md)  
**Related:** [18-testing.md](18-testing.md), [25-beta-release.md](25-beta-release.md), [01-system-overview.md](01-system-overview.md), [ADR-008](decisions/ADR-008-hot-cold-live-queues.md)

---

## Purpose

Make Pulse **production-stable** before Timeline Intelligence (R2) and later platforms: truthful diagnostics, measured budgets, repeatable validation, and overnight soak.

---

## Performance budgets (targets)

| Metric | Target (AGENTS / doc 01) | How measured |
|--------|--------------------------|--------------|
| Cold start (UI to first frame) | &lt; 1 s | Manual stopwatch or ETW; record in release notes honestly |
| Warm start | Informational | Same machine, app already used once |
| Idle UI RSS | &lt; 150 MB | Diagnostics → Flutter RSS or `measure_performance.ps1` |
| Idle CPU | Near zero | Task Manager / Diagnostics service CPU when idle |
| Service working set | Track growth | Diagnostics + soak CSV |
| MCP memory | Track when running | `measure_performance.ps1` (`PulseMCP` / `node`) |
| FPS (Diagnostics open) | ≥ 60 | Diagnostics → Flutter FPS |
| Render latency | Informational | Diagnostics → Frame time |
| IPC ping RTT | &lt; 50 ms | Diagnostics → Ping Service |

**Rule:** Never invent numbers to match targets. If over budget, document the measured value and defer blind optimization.

Diagnostics shows a **Performance budgets** card comparing live samples to these targets when available.

---

## Diagnostics indicators (truthful)

| Indicator | Source | Notes |
|-----------|--------|-------|
| Live events dropped / queue overflow | `live_events_dropped` | Drop **oldest** on full per-connection queue (ADR-008 / doc 05) |
| Live queue depth | Sum across clients | Capacity is **per client** — labels say so |
| Subscription reconnects | Event Log subscriber | Service-side |
| Client reconnect count | Flutter IPC client | With optional advanced history |
| Health sample rate | ~1 Hz when health active | Else 0 |
| IPC ping / snapshot RPC | Client wall clock | Not fabricated service RTT |
| FPS / frame / build / raster / UI RSS | `ClientFrameMetrics` | Only while Diagnostics listens to frame timings |
| Collector latency | **Not supported** | No histogram yet |
| Collector dropped samples | **Not supported** | Use live queue overflow for backpressure |

**Advanced diagnostics** (Settings → Diagnostics): identity (paths, SHA-256, git), IPC throughput, reconnect history, developer tools. Default off.

---

## Validation procedures

Repeatable checks (check off for each release train):

### Cold start
1. Reboot or ensure Pulse.exe not running; PulseService Running.
2. Launch Pulse from Start / installer shortcut.
3. Record time to Connected + first Timeline/Health paint.
4. Note UI RSS after 30 s idle via Diagnostics or `measure_performance.ps1`.

### Service restart
1. Diagnostics → Stop PulseService (UAC) or `sc stop PulseService`.
2. Confirm UI shows offline recovery.
3. Start service; confirm reconnect without app restart; Timeline gap-fill if applicable.

### IPC disconnect / reconnect
1. Diagnostics → **Restart IPC Connection**.
2. Confirm reconnect count increments; health/timeline resume.

### Long-running session
1. Leave UI open ≥ 1 h with Health + Timeline.
2. Confirm no hang; spot-check RSS vs start.

### Overnight soak (≥ 8 h)
1. `powershell -ExecutionPolicy Bypass -File .\tools\scripts\soak_overnight.ps1 -Hours 8`
2. Keep Pulse UI open; machine awake (disable sleep if needed).
3. Archive `artifacts/soak/<stamp>/` with release notes.
4. Fail if unexpected process exit in `soak-events.txt` or unbounded WS growth without explanation.

### Installer / upgrade
1. Clean VM or secondary PC: install current Setup.exe ([25](25-beta-release.md)).
2. Confirm Connected; reboot; service auto-start.
3. Upgrade over previous beta when available; service still healthy.

### Shutdown
1. Exit Pulse UI; service remains Running (expected).
2. Optional: stop service cleanly; no orphaned high-CPU threads.

### Sleep / wake
1. Sleep PC ≥ 2 minutes with Pulse open.
2. Wake; confirm IPC recovers or offline recovery works; no crash.

### Monitor hot-plug
1. Connect/disconnect secondary display.
2. Confirm UI remains usable; no unhandled exception.

### Network changes
1. Disable/enable Wi-Fi or Ethernet briefly.
2. Confirm local IPC unaffected; Network health reflects reality without fabricated rates.

---

## Scripts

| Script | Role |
|--------|------|
| `tools/scripts/measure_performance.ps1` | One-shot process WS + optional diagnostics ping |
| `tools/scripts/soak_overnight.ps1` | Periodic CSV + exit warnings for overnight soak |

Artifacts default under `artifacts/perf/` and `artifacts/soak/` (gitignored if configured).

---

## Crash dumps

Optional local WER dumps (developer machines):

```powershell
# Example — enable local dumps for PulseService (admin); adjust paths per Microsoft docs
New-Item -Force -ItemType Directory "$env:LOCALAPPDATA\CrashDumps" | Out-Null
```

See Microsoft documentation for `LocalDumps` registry keys. Pulse does not ship a crash reporter (no telemetry).

---

## R1 exit

R1 completes when roadmap success metrics in doc 34 are checked, this document’s procedures have been run (soak by maintainer), tests pass, and known limitations are listed in the milestone report.
