# 20 — ETW Integration Plan

## Status: Future milestone (M2) — **not in v1 execution plan**

Pulse v1 does **not** implement ETW adapters, link TDH, or create ETW sessions.

v1 objective is Event Log → Collector → IPC → Timeline only.

---

## Why Deferred

Architecture review: ETW volume, privilege model, and `ProcessTrace`/TDH threading complexity threaten the first pipeline proof. Enable only after Event Log hot/cold paths are stable.

---

## When M2 Starts — Mandatory Constraints

These incorporate accepted review findings:

1. **Do not** decode with TDH inside `EventRecordCallback` / on the `ProcessTrace` thread — copy then decode off-thread
2. Provider allowlist + rate limits before ingest MPSC
3. Capability-gated session control; never silent elevation
4. Prefer Pulse-owned sessions over attaching to arbitrary existing sessions
5. Feed the same Collector MPSC as Event Log

Historical design notes (session modes, provider tables, privilege matrix) from the original draft remain useful planning material but are **superseded for scheduling**: no v1 work items.

---

## Related Documents

- [ADR-007](decisions/ADR-007-event-log-only-v1.md)
- [23 — Architecture Review](23-architecture-review.md)
- [Consuming Events](https://learn.microsoft.com/en-us/windows/win32/etw/consuming-events)
