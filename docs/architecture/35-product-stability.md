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
1. Rebuild service tools so `pulse_diagnostics_ping.exe` prints `SOAK_METRICS` (current tree).
2. `powershell -ExecutionPolicy Bypass -File .\tools\scripts\soak_overnight.ps1 -Hours 8`
3. Keep Pulse UI open; machine awake (disable sleep if needed).
4. Review **final reports**:
   - `tools/soak-results/soak-report-<stamp>.json`
   - `tools/soak-results/soak-report-<stamp>.md`
5. Archive `artifacts/soak/<stamp>/` with the reports.
6. Accept only **PASS** or explicitly justified **PASS WITH WARNINGS**. **FAIL** is an R1 regression.

Verdict fields include runtime, uptimes, CPU/memory peak & growth, queue overflows (`live_events_dropped`), subscription reconnects, service restarts, crash dumps, and Pulse-related Event Log hits.

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
| `tools/scripts/soak_overnight.ps1` | Overnight soak + **JSON/MD verdict** under `tools/soak-results/` |
| `tools/scripts/measure_performance.ps1` | One-shot process WS + optional diagnostics ping |

Session CSV/logs default under `artifacts/soak/` (gitignored). Final reports: `tools/soak-results/soak-report-*.{json,md}`.

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

**Status: Complete — Wave A frozen (2026-08-01).**

### Overnight soak (accepted)

| Field | Value |
|-------|-------|
| Verdict | **PASS** |
| PulseService | Stayed running for entire soak |
| Crashes | None |
| Unexpected service restarts | None |
| IPC disconnect loops | None |
| Unbounded memory growth | None |
| Event Log crash entries | None |

Canonical archive: [archives/r1-soak-pass-2026-08-01.md](archives/r1-soak-pass-2026-08-01.md) (+ `.json`).

### Wave A freeze

R0 + R1 are closed. Future stability regressions found during later waves are fixed as defect work against the frozen Wave A bar; they do not reopen roadmap milestones without an ADR.

Next milestone: **R3 Inventory Engine** — requires accepted [ADR-011](decisions/) and approved [39-inventory-engine-r3.md](39-inventory-engine-r3.md). R2 is frozen ([archives/r2-validation-report-2026-08-02.md](archives/r2-validation-report-2026-08-02.md)).
