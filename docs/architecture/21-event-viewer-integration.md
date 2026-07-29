# 21 — Event Viewer Integration Plan

## Purpose

**Primary and only v1 data source:** Windows Event Log via Wevtapi.

This is the spine of Pulse v1.

References:

- [Windows Event Log](https://learn.microsoft.com/en-us/windows/win32/wes/windows-event-log)
- [Subscribing to Events](https://learn.microsoft.com/en-us/windows/win32/wes/subscribing-to-events)
- [Querying for Events](https://learn.microsoft.com/en-us/windows/win32/wes/querying-for-events)

---

## v1 Channels (Default)

| Channel | Default |
|---------|---------|
| `System` | On |
| `Application` | On |

Optional later (still Event Log only): selected Operational channels. **Security** not required for v1.

**Not supported:** Analytic / Debug subscribe ([EvtSubscribe](https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtsubscribe) limitation).

---

## Subscription Model: Pull (P0)

v1 uses the **pull** model for predictable threading and batching:

1. Create a Windows event for signaling
2. `EvtSubscribe` with that signal (pull), bookmarks as appropriate
3. Dedicated pull thread waits on the signal
4. `EvtNext` in batches (e.g. 16–64)
5. For each event: render **values** needed for Level 1/2 hot path; enqueue `RawObservation` on **MPSC**
6. Do **not** require full XML in the pull loop for every event

### Lazy Level 3

Full XML via `EvtRender(..., EvtRenderEventXml)` on:

- Detail `GetEvent` when user expands raw, and/or
- Async writer if `store_raw: true` (default false)

---

## Historical Query

On adapter start / reconnect gap fill: `EvtQuery` + `EvtNext` for a bounded window (e.g. last hour), then live pull continues.

---

## Bookmarks

Persist per-channel bookmarks under `%ProgramData%\Pulse\data\bookmarks\` for resume across service restarts.

---

## Normalization & Enrichment

Map Wevtapi fields → `PulseEvent` ([09](09-event-model.md)).

Embedded default rules for common IDs (1000, 7036, 6005/6006, …). Overrides optional in ProgramData.

---

## Example Outcome

Application Error 1000 → Level 1 human summary on timeline; Level 2 in detail; XML on expand.

---

## Errors

Channel missing / access denied → adapter status + backoff; other channels continue.

---

## Related Documents

- [06 — Event Engine](06-event-engine.md)
- [08 — Data Flow](08-data-flow.md)
- [11 — Threading](11-threading.md)
- [ADR-007](decisions/ADR-007-event-log-only-v1.md)
- [ADR-008](decisions/ADR-008-hot-cold-live-queues.md)
