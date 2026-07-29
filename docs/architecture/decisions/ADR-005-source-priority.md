# ADR-005: Source Priority (Superseded)

**Status:** Superseded by [ADR-007](ADR-007-event-log-only-v1.md)

**Date:** 2026-07-27

---

## Original Decision

Event Log first; ETW disabled by default; WMI enabled by default.

## Why Superseded

Architecture review and v1 objective: prove one pipeline. WMI-by-default (especially process `WITHIN` polling) and ETW-in-binary scope conflict with simplicity and idle CPU.

**Replacement:** Event Log **only** in v1 execution. ETW = M2, WMI = M3, Plugins = M4.

## References

- [ADR-007](ADR-007-event-log-only-v1.md)
