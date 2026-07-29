# ADR-001: C++20 Backend

**Status:** Accepted

**Date:** 2026-07-27

---

## Context

Pulse requires a native Windows backend to consume Event Log (Wevtapi), ETW (evntrace/TDH), and WMI (MI) APIs. The backend must run as a Windows Service, handle high-frequency event streams, and maintain low resource usage.

## Decision

Use **C++20 with MSVC** for the PulseService backend.

## Alternatives Considered

| Alternative | Pros | Cons |
|-------------|------|------|
| **C++20 / MSVC** | Direct Win32 API access; all Microsoft samples in C/C++; no FFI overhead; mature service patterns | Manual memory management; longer compile times |
| Rust | Memory safety; modern tooling; good FFI | Fewer Windows diagnostic samples; smaller ecosystem for Wevtapi/TDH; team learning curve |
| C# / .NET | Productive; good Windows support | Heavier runtime; less common for long-lived SCM services consuming ETW; GC pauses at high event rates |
| Go | Simple concurrency; fast builds | Poor Win32 API access; no direct Wevtapi/TDH bindings; not typical for Windows services |

## Rationale

1. Microsoft documents all target APIs (Wevtapi, evntrace, TDH, MI) with C/C++ samples
2. No translation layer between API samples and implementation
3. Zero runtime dependency (no .NET CLR, no GC)
4. Direct control over threading, memory, and performance
5. Standard pattern for Windows services (Event Viewer, Sysinternals, Process Monitor are native)

## Consequences

- Team must be proficient in C++20 and Win32
- vcpkg for dependency management (protobuf, sqlite, gtest)
- CMake build system
- Manual resource management (RAII patterns required)

## References

- [AGENTS.md](../../../AGENTS.md) — Architecture section
- [19 — Windows APIs](../19-windows-apis.md)
