# 07 — Timeline Engine (Collector Queries)

## Purpose

Query and live subscription API over Event Log–sourced events. In v1 this is a **facade of the Collector**, not a heavy separate subsystem.

---

## Operations

### SubscribeLive

Register connection → attach empty live queue → receive `PulseEventSummary` batches.

Filter: severity, channel, search text (simple), optional process name if present in event fields.

### QueryRange

SQLite-backed (cold path). Newest-first pagination with opaque cursor. Page size default 100.

### GetEvent

Full event: Level 1+2 always; Level 3 if stored or lazily rendered/re-fetched by RecordId when possible.

---

## Live + Historical Merge (UI)

1. Initial `QueryRange` (e.g. last hour)
2. `SubscribeLive`
3. Prepend live summaries; dedupe by `event_id`
4. Scroll back with cursor
5. On reconnect: gap-fill `QueryRange` then resubscribe

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
| QueryRange 100 rows | < 20 ms p95 (warm DB) |
| GetEvent | < 5 ms p95 without lazy raw; raw may be slower |
| Live enqueue | Non-blocking from ingest |

---

## Explicitly Out of v1

- Process-centric story mode (nice-to-have later)
- Cross-source correlation
- FTS5 requirement (optional later)
- Replay / export

---

## Related Documents

- [05 — IPC](05-ipc.md)
- [06 — Event Engine](06-event-engine.md)
- [08 — Data Flow](08-data-flow.md)
