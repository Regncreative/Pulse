# 14 — Plugin Architecture (Future)

## Status: Future milestone (M4) — **not in v1 execution plan**

No PluginManager, PluginHost, or plugin loading ships in Pulse v1.

---

## Why Deferred

v1 proves Event Log → Collector → IPC → Timeline. Plugins add process isolation, ABI, and security surface before the spine is proven.

---

## Future Design (Unchanged Intent)

- Out-of-process hosts only
- Stable C ABI
- Events enter Collector via validated adapter
- `SOURCE_PLUGIN` reserved in schema

Full draft ABI and host model remain as previously written for planning; **do not implement stubs** in v1.

---

## Related Documents

- [ADR-006](decisions/ADR-006-plugin-deferral.md)
- [ADR-007](decisions/ADR-007-event-log-only-v1.md)
