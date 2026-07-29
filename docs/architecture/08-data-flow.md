# 08 — Data Flow

## Purpose

End-to-end path for **v1 Event Log only**.

---

## Live Path (Hot)

```mermaid
sequenceDiagram
  participant Win as WindowsEventLog
  participant Adapter as EventLogAdapter_Pull
  participant Ingest as IngestThread
  participant LiveQ as PerConnQueue
  participant IPC as IpcWorker
  participant App as PulseApp_IOIsolate

  Win->>Adapter: New events available
  Adapter->>Adapter: EvtNext batch
  Adapter->>Ingest: MPSC RawObservation
  Ingest->>Ingest: Normalize Dedupe Enrich
  Ingest->>LiveQ: try_push summary
  IPC->>LiveQ: drain
  IPC->>App: LiveEventBatch
  App->>App: Forward to UI isolate
```

**Latency budget (Event Log rates):** pull/normalize/enrich/enqueue under 10 ms p95; IPC to UI under 50 ms p95 under normal load.

Ingest **does not** wait for SQLite or pipe writes.

---

## Cold Persist Path

```mermaid
sequenceDiagram
  participant Ingest
  participant Writer as SqliteWriter
  participant DB as SQLite

  Ingest->>Writer: WriteJob summary metadata
  Writer->>DB: Batch INSERT
```

---

## Detail Path (Lazy Level 3)

```mermaid
sequenceDiagram
  participant UI as PulseApp
  participant IPC as IpcServer
  participant Col as Collector
  participant Store as Storage

  UI->>IPC: GetEventRequest
  IPC->>Col: GetEvent
  Col->>Store: Load summary plus optional raw
  alt raw missing and store_raw false
    Col->>Col: Optional re-render via EventLogAdapter provenance
  end
  Col-->>UI: PulseEvent Level1 2 3
```

---

## Example: Application Error 1000

1. Pull delivers event from Application channel  
2. Normalize extracts process / exception fields  
3. Embedded rule → Level 1: “{process} stopped responding and was closed.”  
4. Level 2: technical Application Error summary  
5. Summary pushed to live subscribers  
6. Writer persists index row (XML later or on demand)

---

## Related Documents

- [06 — Event Engine](06-event-engine.md)
- [21 — Event Viewer Integration](21-event-viewer-integration.md)
