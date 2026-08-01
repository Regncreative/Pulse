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

### Wire `TimelineEvent` (current + R2 additive)

IPC carries Level 1 title/summary from the Event Intelligence Engine, plus channel, provider, Win32 event id, record id, message, recommendation, importance, and `category` string (e.g. `Crash`, `Power`, `Update`).

**R2 additive system fields** (empty / `has_* = false` when Windows does not provide them — never invented):

task, opcode, keywords, process_id, process_name (best-effort image name when PID still resolvable), thread_id, user_sid, activity_id, related_activity_id, level_name.

**Level 3 raw XML:** not on list rows; fetched via `GetTimelineEventDetail` and may populate `raw_xml` on the detail response only.

Canonical plan: [36-timeline-intelligence-r2.md](36-timeline-intelligence-r2.md).

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

Used for dedup and lazy raw re-fetch. Stable Timeline ids include channel + record id + event id + timestamp.

---

## Intelligence categories (Phase 4)

| Category | Typical diagnostics |
|----------|---------------------|
| Crash | Application Error 1000, Hang 1002, bug check / WER 1001 |
| Service | SCM 7036 / 7040 / 7023 / 7031 / 7034 |
| Power | Kernel-Power 41/42/107, EventLog 6008, Power-Troubleshooter 1 |
| Boot | Kernel-General 12/13, EventLog 6005/6006, User32 1074 |
| Update | WindowsUpdateClient 19/20/43/44 |
| Device / Driver | Kernel-PnP 400/410/411, SCM 7045 |
| Security | Security-Auditing 4624/4634 (when channel readable) |
| Storage | disk 7 / 51 |
| Network / COM / HTTP / Time | Existing rules |

Rules use Microsoft-documented Event IDs only. Uncertain IDs are omitted.

---

## UI binding

| UI | Level |
|----|-------|
| Timeline row | 1 |
| Detail body | 2 |
| Raw expand | 3 (fetch if needed) |

Flutter Timeline filters by severity, channel/source, and category without changing the live stream.

---

## Related Documents

- [06 — Event Engine](06-event-engine.md)
- [10 — Storage](10-storage.md)
- [21 — Event Viewer Integration](21-event-viewer-integration.md)
