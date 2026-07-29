# 22 — WMI Integration Plan

## Status: Future milestone (M3) — **not in v1 execution plan**

Pulse v1 does **not** implement WMI/MI adapters or enable WMI in config.

---

## Why Deferred

1. v1 proves Event Log pipeline only  
2. Architecture review rejected `__InstanceCreationEvent WITHIN n` process polling (missed short-lived processes; idle CPU)  
3. Process lifecycle belongs with ETW Kernel-Process (M2) or WMI **intrinsic** trace classes in M3 — never v1 polling

---

## When M3 Starts — Constraints

- Prefer event-driven indications (`Win32_ProcessStartTrace` / `StopTrace`) over `WITHIN` polling on `Win32_Process`
- Narrow WQL; read-only; temporary consumers only
- Feed Collector MPSC; same hot/cold rules as v1
- Keep MI as preferred API; COM fallback only if required

---

## Related Documents

- [ADR-007](decisions/ADR-007-event-log-only-v1.md)
- [23 — Architecture Review](23-architecture-review.md)
- [Monitoring Events](https://learn.microsoft.com/en-us/windows/win32/wmisdk/monitoring-events)
