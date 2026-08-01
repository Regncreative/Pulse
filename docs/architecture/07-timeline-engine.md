# 07 — Timeline Engine (Collector Queries)

## Purpose

Query and live subscription API over Event Log–sourced events. In v1 this is a **facade of the Collector**, not a heavy separate subsystem.

Phase 4 expands Timeline into a **diagnostics history** by querying multiple Event Log channels (still Wevtapi only — ADR-007). ETW Timeline ingest remains out of scope.

---

## Operations

### SubscribeLive

Register connection → attach empty live queue → receive `PulseEventSummary` batches.

Filter (Flutter client): severity, **channel/source**, **intelligence category**, search text (simple), optional process name if present in event fields.

Live monitoring starts one `EvtSubscribe` per accessible diagnostics channel and fans events into the same per-connection queues.

### QueryRange / Snapshot

v1 milestone path: `GetTimelineSnapshot` → `EventLogCollector::CollectLatestMulti` across accessible diagnostics channels, merge newest-first, bound to `limit` (max 500).

Per-channel fair share prevents one busy log from starving others. Inaccessible channels are skipped and logged; the snapshot fails only when **no** channel succeeds.

SQLite-backed cold-path QueryRange remains the longer-term design (newest-first pagination with opaque cursor; page size default 100).

### GetEvent

Full event: Level 1+2 always; Level 3 if stored or lazily rendered/re-fetched by RecordId when possible.

---

## Live + Historical Merge (UI)

1. Initial snapshot (multi-channel diagnostics set; clients may still send `channel=System`)
2. `StartLiveMonitoring`
3. Prepend live summaries; dedupe by `event_id`
4. Scroll back with cursor (when QueryRange lands)
5. On reconnect: gap-fill snapshot then resubscribe

---

## Ordering

| Context | Order |
|---------|-------|
| Global timeline | Newest first |
| Historical pages | Newest first |

---

## Performance

| Op | Target |
|----|--------|
| Snapshot ≤100 rows (warm) | Keep UI responsive; bound total events |
| GetEvent | < 5 ms p95 without lazy raw; raw may be slower |
| Live enqueue | Non-blocking from ingest |

Publisher metadata is cached in Wevt helpers so formatting does not dominate snapshot latency.

---

## Explicitly Out of v1 / Phase 4

- ETW as a Timeline source (Health may use ETW — ADR-009; Timeline does not)
- Process-centric story mode
- Cross-source correlation
- FTS5 requirement (optional later)
- Replay / session recording

---

## Related Documents

- [05 — IPC](05-ipc.md)
- [06 — Event Engine](06-event-engine.md)
- [08 — Data Flow](08-data-flow.md)
- [21 — Event Viewer Integration](21-event-viewer-integration.md)
- [29 — System Health quality milestone](29-system-health-quality-milestone.md)
