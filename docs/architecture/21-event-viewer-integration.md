# 21 — Event Viewer Integration Plan

## Purpose

**Primary and only Timeline data source:** Windows Event Log via Wevtapi (ADR-007).

This is the spine of Pulse Timeline. Health may use ETW separately (ADR-009); Timeline does not ingest ETW.

References:

- [Windows Event Log](https://learn.microsoft.com/en-us/windows/win32/wes/windows-event-log)
- [Subscribing to Events](https://learn.microsoft.com/en-us/windows/win32/wes/subscribing-to-events)
- [Querying for Events](https://learn.microsoft.com/en-us/windows/win32/wes/querying-for-events)

---

## Diagnostics channels (Phase 4)

Pulse attempts the following channels under the service account (typically LocalService). Optional channels are skipped when missing or access-denied; other channels continue.

| Channel | Kind | Notes under LocalService |
|---------|------|---------------------------|
| `System` | Required | Expected to succeed |
| `Application` | Optional | Usually readable |
| `Setup` | Optional | May be empty or sparse |
| `Microsoft-Windows-WindowsUpdateClient/Operational` | Optional | Present on modern Windows; skip if missing |
| `Microsoft-Windows-Kernel-PnP/Configuration` | Optional | Device configure/start events |
| `Microsoft-Windows-Kernel-Power/Thermal-Operational` | Optional | Included when present; thermal-specific rules only when Microsoft-documented |
| `Microsoft-Windows-Kernel-Boot/Operational` | Optional | Boot-related operational log when present |
| `Security` | Probe (`EvtOpenLog`) | **Often fails** under LocalService — skip and log; do not fail the snapshot |

Clients that send `channel=System` (historical default) receive the **diagnostics multi-channel set**. Explicit non-default channel names remain reserved for single-channel requests on snapshot.

**Not supported:** Analytic / Debug subscribe ([EvtSubscribe](https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtsubscribe) limitation).

---

## Subscription Model

### Snapshot (historical)

`EvtQuery` + `EvtNext` per accessible channel → merge by timestamp → bound to IPC `limit` (≤500) with fair per-channel share.

### Live

One `EvtSubscribe(..., EvtSubscribeToFutureEvents)` per accessible channel. Callback parse via shared system render context path in `EventLogCollector::ParseEvtHandle`. Reconnect remains per-subscriber.

### Lazy Level 3

Full XML via `EvtRender(..., EvtRenderEventXml)` on:

- Detail `GetEvent` when user expands raw, and/or
- Async writer if `store_raw: true` (default false)

---

## Normalization & Enrichment

Map Wevtapi fields → `TimelineEvent` / `PulseEvent` ([09](09-event-model.md)).

Embedded intelligence + humanizer rules for documented IDs (crashes, SCM, Kernel-Power, Windows Update, Kernel-PnP, Security logon when available, disk errors, …). Overrides optional in ProgramData (design).

---

## Example Outcome

Application Error 1000 → Level 1 “Application Crashed” on timeline; Level 2 technical line with provider/id/channel; XML on expand when lazy raw lands.

---

## Errors

Channel missing / access denied → skip that channel + structured log; continue others. Snapshot fails only if every channel fails.

---

## Related Documents

- [06 — Event Engine](06-event-engine.md)
- [07 — Timeline Engine](07-timeline-engine.md)
- [08 — Data Flow](08-data-flow.md)
- [11 — Threading](11-threading.md)
- [ADR-007](decisions/ADR-007-event-log-only-v1.md)
- [ADR-008](decisions/ADR-008-hot-cold-live-queues.md)
- [29 — System Health quality milestone](29-system-health-quality-milestone.md)
