# Roadmap: Task Manager–style Application grouping

**Status:** Implemented (presentation layer) — 2026-08  
**Constraint:** PID inventory remains source of truth; collector / IPC unchanged

---

## Current model (keep)

| Layer | Behavior |
|-------|----------|
| Service | Emits **one row per process** (`HealthProcessEntry`: PID + CreateTime + metrics) |
| Wire | `HealthProcessInventoryUpdate` upserts/removes by PID |
| Flutter store | `ProcessInventoryStore` keyed by PID |
| UI | **Grouped** Apps / Background / Windows via `AppGroupEngine` |

---

## What shipped (Phase A)

1. Flat inventory ingest unchanged.
2. `AppGroupEngine` groups by **normalized executable basename** (`chrome.exe`, `Cursor.exe`, …).
3. Group row shows **display name + member count** and **summed** CPU / Memory / Disk / Network.
4. Expand (chevron) reveals each child: icon, `name (PID)`, per-PID metrics.
5. Group category: **Apps** if any member owns a visible top-level window; else Background / Windows from members.
6. Friendly labels for common apps (Chrome, Cursor, Discord, …) via `ProcessDisplayNames`.

Sources:

- `apps/pulse_app/lib/presentation/health/widgets/process_inventory/app_group_engine.dart`
- `apps/pulse_app/lib/presentation/health/widgets/process_inventory/process_inventory_list.dart`

---

## Aggregation rules

| Metric | Group value |
|--------|-------------|
| CPU | Sum of member `%` |
| Memory | Sum of private WS bytes |
| Disk | Sum of member B/s |
| Network | Sum of member B/s (often `—` until ETW) |

---

## Not yet (Phase B+)

- AppUserModelID / package family identity
- Parent-PID trees when basenames differ (rare helpers)
- Job object membership
- Per-process network via ETW ([24](24-health-metrics-task-manager.md))

---

## Acceptance

| Check | Expectation |
|-------|-------------|
| Collapsed Apps | `Google Chrome (N)`, `Cursor (N)` with totals ≈ TM Apps |
| Expand | Every child PID visible with own metrics |
| Select child | Detail panel uses that PID |
| Collector / IPC | Unchanged |
