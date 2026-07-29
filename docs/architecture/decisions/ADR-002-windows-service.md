# ADR-002: Windows Service Process Model

**Status:** Accepted

**Date:** 2026-07-27

---

## Context

Pulse must observe Windows continuously, including when the UI is closed. The collector must survive user logoff and system events. Privilege handling for ETW and Event Log must be centralized.

## Decision

Run the collector as a **Windows Service (`PulseService`)** with a separate **Flutter Desktop client (`PulseApp`)**.

Default service account: `NT AUTHORITY\LocalService`.

## Alternatives Considered

| Alternative | Pros | Cons |
|-------------|------|------|
| **Windows Service + UI client** | Survives logoff; SCM recovery; standard pattern; centralized privileges | Two processes; IPC required; install requires admin |
| In-process Flutter plugin | Single process; no IPC | Dies with UI; cannot survive logoff; privilege model wrong |
| User-mode tray application | Simple; no admin install | Dies on logoff; no SCM recovery; cannot run as LocalService |
| Scheduled task | No service registration | No real-time lifecycle; no recovery; awkward for continuous observation |

## Rationale

1. AGENTS.md specifies "Native Windows service" as backend architecture
2. Observation must continue when UI is closed ("What is Windows doing right now?")
3. SCM provides automatic crash recovery
4. LocalService provides minimal privilege footprint
5. Matches industry pattern (Splunk forwarder, Datadog agent, OSQuery as service)

## Consequences

- Admin required for one-time install
- IPC layer required between service and UI (see ADR-003)
- Debug console mode (`--console`) needed for development workflow
- Service recovery policy must be configured

## References

- [04 — Native Service](../04-native-service.md)
- [01 — System Overview](../01-system-overview.md)
