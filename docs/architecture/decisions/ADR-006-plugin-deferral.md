# ADR-006: Plugin System Deferred

**Status:** Accepted

**Date:** 2026-07-27

---

## Context

Long-term extensibility vs v1 focus.

## Decision

Design out-of-process plugins for the future; **ship zero plugin runtime in v1** (and do not implement stubs).

Aligned with [ADR-007](ADR-007-event-log-only-v1.md): v1 execution plan excludes plugins.

## References

- [14 — Plugins (Future)](../14-plugins-future.md)
- [ADR-007](ADR-007-event-log-only-v1.md)
