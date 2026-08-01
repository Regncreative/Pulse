# 20 — ETW Integration Plan

## Status

| Area | Status |
|------|--------|
| **Health per-process network** (`NetworkEtwEngine` / `PulseHealthNet`) | **Implemented** (ADR-009) |
| **Timeline ETW ingest** | **Deferred** — Event Log only (ADR-007 unchanged) |

Pulse Timeline v1 does **not** implement general ETW adapters, link TDH for Timeline, or feed ETW into the Collector MPSC.

System Health uses a **scoped** Pulse-owned real-time session for Kernel-Network send/recv byte aggregation only. That path must not call TDH inside `EventRecordCallback`.

---

## Why Timeline ETW Remains Deferred

Architecture review: ETW volume, privilege model, and `ProcessTrace`/TDH threading complexity threaten the first Timeline pipeline proof. Enable Timeline ETW only after Event Log hot/cold paths are stable.

---

## Health Network Engine (shipped)

- Session name: `PulseHealthNet` (not NT Kernel Logger)
- Provider: `Microsoft-Windows-Kernel-Network` `{7dd42a49-5329-4832-8dfd-43d979153a88}`
- Callback: light `EVENT_RECORD` parse (PID + size + opcode/Id) → cumulative counters under mutex
- Sampler (~1 Hz): `Snapshot` → delta/dt → `HealthProcessEntry` net fields
- On `StartTrace` / `EnableTraceEx2` failure: leave `has_net_*` unset — never invent rates

Code: `service/pulse_service/src/collectors/network_etw_engine.*`

---

## When Timeline M2 Starts — Mandatory Constraints

These incorporate accepted review findings:

1. **Do not** decode with TDH inside `EventRecordCallback` / on the `ProcessTrace` thread — copy then decode off-thread
2. Provider allowlist + rate limits before ingest MPSC
3. Capability-gated session control; never silent elevation
4. Prefer Pulse-owned sessions over attaching to arbitrary existing sessions
5. Feed the same Collector MPSC as Event Log

Historical design notes (session modes, provider tables, privilege matrix) from the original draft remain useful planning material but are **superseded for scheduling**: no Timeline ETW work items in v1.

---

## Related Documents

- [ADR-007](decisions/ADR-007-event-log-only-v1.md)
- [ADR-009](decisions/ADR-009-health-network-etw.md)
- [23 — Architecture Review](23-architecture-review.md)
- [24 — Health metrics](24-health-metrics-task-manager.md)
- [Consuming Events](https://learn.microsoft.com/en-us/windows/win32/etw/consuming-events)
