# 07 — Timeline Engine (Collector Queries)

## Purpose

Query and live subscription API over Event Log–sourced events. In v1 this is a **facade of the Collector**, not a heavy separate subsystem.

Phase 4 expands Timeline into a **diagnostics history** by querying multiple Event Log channels (still Wevtapi only — ADR-007). ETW Timeline ingest remains out of scope.

---

## Operations

### SubscribeLive

Register connection → attach empty live queue → receive `PulseEventSummary` batches.

Filter / search (Flutter client, R2 Timeline Intelligence): severity, channel/source, intelligence category, provider, Event ID, computer, process/PID (when present), date range, keyword, and case-insensitive full-text over message / XML (XML when loaded). See [36-timeline-intelligence-r2.md](36-timeline-intelligence-r2.md).

Live monitoring starts one `EvtSubscribe` per accessible diagnostics channel and fans events into the same per-connection queues.

### QueryRange / Snapshot

v1 milestone path: `GetTimelineSnapshot` → `EventLogCollector::CollectLatestMulti` across accessible diagnostics channels, merge newest-first, bound to `limit` (max 500).

Per-channel fair share prevents one busy log from starving others. Inaccessible channels are skipped and logged; the snapshot fails only when **no** channel succeeds.

SQLite-backed cold-path QueryRange remains the longer-term design (newest-first pagination with opaque cursor; page size default 100).

### GetEvent / GetTimelineEventDetail

List rows carry Level 1+2 plus compact Wevtapi system metadata (task, opcode, keywords, PID, SID, activity IDs when present). **Raw Event XML** is Level 3 and is **lazy-loaded** via `GetTimelineEventDetail` (channel + record id) so 100k+ timelines stay memory-safe.

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
| GetTimelineEventDetail (raw XML) | Best-effort; may be slower than summary path |
| Live enqueue | Non-blocking from ingest |

Publisher metadata is cached in Wevt helpers so formatting does not dominate snapshot latency.

---

## R2 — Flagship Timeline (Event Log only)

Within Windows Event Log data (not ETW/WMI):

- Incident collapse for **documented** correlation rules (no clustering without a rule)
- Root-cause hints only from static documented rules (no AI)
- Bookmarks, pins, saved searches, event links, rich metadata badges
- Export preserving filters / marks / correlation groups

See [36-timeline-intelligence-r2.md](36-timeline-intelligence-r2.md).

**Wevtapi subscribe resume bookmarks:** deferred (explicit note; not required to close R2).

## Explicitly Out of v1 / Phase 4 / R2

- ETW as a Timeline source (Health may use ETW — ADR-009; Timeline does not)
- Cross-source correlation (Event Log ↔ ETW ↔ WMI) — later Observability Platform
- Process-centric story mode
- FTS5 requirement (optional later)
- Replay / session recording
- Fabricated incidents, correlations, or AI-generated explanations

---

## Related Documents

- [05 — IPC](05-ipc.md)
- [06 — Event Engine](06-event-engine.md)
- [08 — Data Flow](08-data-flow.md)
- [09 — Event Model](09-event-model.md)
- [36 — Timeline Intelligence R2](36-timeline-intelligence-r2.md)
- [21 — Event Viewer Integration](21-event-viewer-integration.md)
- [29 — System Health quality milestone](29-system-health-quality-milestone.md)
