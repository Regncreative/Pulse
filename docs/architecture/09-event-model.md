# 09 — Event Model

## Purpose

Canonical `PulseEvent` for Pulse. v1 **produces** only `SOURCE_EVENT_LOG`. Schema remains source-agnostic for future milestones.

---

## Design Principles

1. Source-agnostic schema (future ETW/WMI/plugin values reserved)
2. Three-level hierarchy; UI never inverts it
3. Immutable after enrichment
4. Stable IDs
5. Provenance for dedup and lazy Level 3

---

## Schema (Protobuf sketch)

```protobuf
message PulseEvent {
  string event_id = 1;
  uint64 timestamp_unix_ns = 2;
  SourceType source = 3;           // v1: SOURCE_EVENT_LOG
  Severity severity = 4;
  string category = 5;
  string summary = 10;             // Level 1 — always
  string technical_summary = 11;   // Level 2 — always
  RawPayload raw = 12;             // Level 3 — may be empty until lazy load
  bool raw_available = 13;         // hint for UI
  ProcessInfo process = 20;
  string computer_name = 21;
  SourceMetadata source_metadata = 30;
  bool parse_error = 40;
}

enum SourceType {
  SOURCE_UNKNOWN = 0;
  SOURCE_EVENT_LOG = 1;
  SOURCE_ETW = 2;      // future
  SOURCE_WMI = 3;      // future
  SOURCE_PLUGIN = 4;   // future
}
```

### Live summary

`PulseEventSummary`: id, timestamp, source, severity, category, summary (Level 1), optional process_name. **No Level 3.**

---

## Event Log metadata

```protobuf
message EventLogMetadata {
  string channel = 1;
  string provider_name = 2;
  uint32 event_id = 3;
  uint64 record_id = 4;
}
```

Used for dedup and lazy raw re-fetch.

---

## UI binding

| UI | Level |
|----|-------|
| Timeline row | 1 |
| Detail body | 2 |
| Raw expand | 3 (fetch if needed) |

---

## Related Documents

- [06 — Event Engine](06-event-engine.md)
- [10 — Storage](10-storage.md)
