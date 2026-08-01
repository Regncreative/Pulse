# ADR-009: Health per-process network via ETW

**Status:** Accepted

**Date:** 2026-08-01

---

## Context

Per-process network rates cannot use `GetPerTcpConnectionEStats` under `LocalService` (enable-first + admin; garbage rates observed). Task Manager / Resource Monitor / System Informer use ETW. ADR-007 deferred all ETW for Timeline v1; System Health now needs a scoped exception.

## Decision

1. Introduce a **Pulse-owned real-time ETW session** (`PulseHealthNet`) used **only** for System Health per-process network aggregation.
2. Prefer **non–NT Kernel Logger** sessions so `LocalService` can control them ([StartTrace](https://learn.microsoft.com/en-us/windows/win32/api/evntrace/nf-evntrace-starttracea)).
3. Enable **`Microsoft-Windows-Kernel-Network`** (and related send/recv events as available). If `StartTrace` / `EnableTraceEx2` fails, leave `has_net_*` unset — never invent rates.
4. Decode **off** the `ProcessTrace` callback thread: callback copies PID + size only; aggregate under a mutex; health sampler reads a snapshot (~1 Hz).
5. Timeline remains Event Log–only (ADR-007 unchanged for Timeline). This ADR does **not** open general ETW Timeline ingest.

## Consequences

- New collector module `network_etw_engine`
- Health inventory gains real `net_bps` / upload / download when the session starts
- Diagnostics should surface ETW session up/down + last error
- Docs 20 / 24 / 29 updated

## References

- [20 — ETW Integration](../20-etw-integration.md)
- [24 — Health metrics](../24-health-metrics-task-manager.md)
- [ADR-007](ADR-007-event-log-only-v1.md)
