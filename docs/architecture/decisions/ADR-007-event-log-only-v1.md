# ADR-007: Event Log Only for Pulse v1

**Status:** Accepted

**Date:** 2026-07-27

---

## Context

The original architecture planned Event Log + ETW + WMI for v1 (with ETW off by default, WMI on). The architecture review and product goal conflict with that breadth.

**v1 objective:** Prove a stable end-to-end pipeline:

```
Windows Event Log → Collector → IPC → Timeline → Human-readable events
```

Priorities: simplicity, responsiveness, maintainability over feature count.

## Decision

1. **v1 implements only Windows Event Log** (Wevtapi pull) as a data source  
2. **ETW** is documented as **milestone M2** — no adapter code, no TDH link, no config surface in v1 execution  
3. **WMI** is documented as **milestone M3** — no adapter code; no `WITHIN` process polling design for v1  
4. **Plugins** remain **milestone M4** (ADR-006)  
5. Schema may reserve `SOURCE_ETW` / `SOURCE_WMI` / `SOURCE_PLUGIN` enum values but v1 produces only `SOURCE_EVENT_LOG`

This **supersedes ADR-005** for v1 scope.

## Alternatives Considered

| Alternative | Pros | Cons |
|-------------|------|------|
| **Event Log only** | Smallest proof; idle-friendly; clear MVP | No process lifecycle until M2/M3 |
| Event Log + WMI | More timeline richness | WMI complexity; polling risk; delays proof |
| Full three sources | Maximum coverage | Highest failure risk for first release |

## Consequences

- Folder structure and build omit ETW/WMI  
- Docs 20/22/14 are future-only  
- Success metric: human-readable Event Log timeline over IPC, stable under normal Event Log load  

## References

- [README](../README.md)
- [21 — Event Viewer Integration](../21-event-viewer-integration.md)
- [20 — ETW (Future)](../20-etw-integration.md)
- [22 — WMI (Future)](../22-wmi-integration.md)
- [23 — Architecture Review](../23-architecture-review.md)
