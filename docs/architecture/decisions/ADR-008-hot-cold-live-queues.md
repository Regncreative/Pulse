# ADR-008: Hot/Cold Path and Per-Connection Live Queues

**Status:** Accepted

**Date:** 2026-07-27

---

## Context

Architecture review P0 items:

- Shared ring multi-reader head is unsafe  
- Sync SQLite on ingest blocks live delivery  
- Sync IPC notify from ingest couples collection to slow clients  
- Flutter sync FFI on UI isolate blocks frames  
- Event Log push+EvtRender XML on callback path risks loss  

## Decision

Accept all P0 recommendations:

| P0 | Decision |
|----|----------|
| P0-1 | **Per-connection bounded live queues**; no shared ring consumer head |
| P0-2 | Adapter → ingest queue is **MPSC** |
| P0-3 | **Async SQLite writer**; ingest never waits on disk |
| P0-4 | Event Log **pull** + **lazy Level 3** XML |
| P0-5 | PulseApp **I/O isolate** owns all pipe FFI |

Additionally:

- Document **pipe SDDL** explicitly ([05](../05-ipc.md))  
- Max IPC frame **2 MB**  
- **Embedded** default enrichment rules  

## Alternatives Considered

| Alternative | Why rejected |
|-------------|--------------|
| Shared lock-free ring with atomic head | Incorrect under multi-reader |
| Persist-then-notify | Latency and stall under disk pressure |
| Push callback + full XML always | Thread-pool stalls; lost events |
| Main-isolate FFI Futures | Still blocks UI on sync ReadFile |

## Consequences

- Implementation must include connection-scoped queues and a writer thread before feature work  
- UI may see “events dropped” under backpressure — must be visible, not silent  
- Level 3 may be empty until detail fetch  

## References

- [01 — System Overview](../01-system-overview.md)
- [05 — IPC](../05-ipc.md)
- [06 — Event Engine](../06-event-engine.md)
- [11 — Threading](../11-threading.md)
- [21 — Event Viewer](../21-event-viewer-integration.md)
- [23 — Architecture Review](../23-architecture-review.md)
