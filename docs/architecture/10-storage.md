# 10 — Storage Strategy

## Purpose

v1 storage: **responsive live path** + **durable Event Log history**. No cloud.

---

## Two Paths

| Tier | Technology | Role |
|------|------------|------|
| Hot | Recent **summary cache** (single-writer) | Optional fast recent read; **not** a multi-reader ring with shared head |
| Live | **Per-connection queues** | Live UI feed (see IPC / threading) |
| Cold | SQLite WAL | History, QueryRange, GetEvent index |
| Raw (optional) | Separate store or lazy re-fetch | Level 3; default **off** (`store_raw: false`) |

**Removed from v1 design:** shared ring buffer with atomic head consumed by multiple IOCP workers ([architecture review P0-1](23-architecture-review.md)).

---

## Summary Cache

- Capacity default: 10,000 summaries
- Single writer: ingest thread
- Readers may snapshot under defined sync (copy or seqlock); no shared consumer cursor
- Lost on service restart (SQLite retains history)

---

## SQLite

Path: `%ProgramData%\Pulse\data\pulse.db`  
Mode: WAL, synchronous NORMAL  
Writer: **dedicated thread** only

### Schema (v1)

```sql
CREATE TABLE events (
    rowid          INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id       TEXT NOT NULL UNIQUE,
    timestamp_ns   INTEGER NOT NULL,
    source         INTEGER NOT NULL,  -- SOURCE_EVENT_LOG
    severity       INTEGER NOT NULL,
    category       TEXT NOT NULL,
    summary        TEXT NOT NULL,
    technical      TEXT NOT NULL,
    process_id     INTEGER,
    process_name   TEXT,
    computer_name  TEXT,
    channel        TEXT,
    provider_name  TEXT,
    event_log_id   INTEGER,
    record_id      INTEGER,
    parse_error    INTEGER DEFAULT 0,
    created_at     INTEGER NOT NULL
);

CREATE INDEX idx_events_timestamp ON events(timestamp_ns DESC);
CREATE INDEX idx_events_channel ON events(channel, timestamp_ns DESC);
CREATE INDEX idx_events_severity ON events(severity, timestamp_ns DESC);
```

**No `raw_data` BLOB on the primary table** in v1 default.

Optional later:

```sql
CREATE TABLE event_raw (
    event_id TEXT PRIMARY KEY,
    format INTEGER,
    content_type TEXT,
    data BLOB
);
```

Or re-fetch XML via Wevtapi using `channel + record_id` while the log still retains it.

### FTS

**Not required for v1.** Simple `LIKE` / prefix filters acceptable. FTS5 may be added in a later milestone without blocking the pipeline proof.

---

## Retention

Default 7 days; hourly purge on writer/background thread. Max DB size soft cap (e.g. 512–1024 MB) with warning.

---

## Privacy

Local only; redact sensitive patterns in logs; BitLocker covers disk at rest for v1.

---

## Related Documents

- [06 — Event Engine](06-event-engine.md)
- [11 — Threading](11-threading.md)
- [ADR-004](decisions/ADR-004-storage-strategy.md)
- [ADR-008](decisions/ADR-008-hot-cold-live-queues.md)
