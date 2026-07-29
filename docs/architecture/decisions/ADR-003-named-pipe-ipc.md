# ADR-003: Named Pipe IPC with Protobuf

**Status:** Accepted

**Date:** 2026-07-27

---

## Context

PulseApp (Flutter) and PulseService (C++) are separate processes that must communicate for live events, historical queries, and configuration. AGENTS.md prohibits HTTP for local communication.

## Decision

Use **Windows named pipes** (`\\.\pipe\PulseService`) with **length-prefixed Protobuf** messages.

Flutter connects via Dart FFI (`win32` package), not MethodChannel.

## Alternatives Considered

| Alternative | Pros | Cons |
|-------------|------|------|
| **Named pipes + Protobuf** | Windows-native; ACL support; duplex; efficient binary; schema evolution | Custom framing protocol; no Dart-native pipe library |
| Named pipes + JSON | Human-readable; easy debug | Expensive parse at ETW rates; no schema enforcement |
| gRPC over localhost | Rich RPC framework; streaming | Uses HTTP/2; violates AGENTS.md; unnecessary complexity |
| Shared memory + events | Lowest latency | No request/response; complex synchronization; no schema |
| Flutter MethodChannel | Built-in Flutter IPC | Only reaches embedder process, not separate service |
| ALPC | Lowest latency IPC on Windows | Complex API; no Dart support; overkill for v1 |

## Rationale

1. Named pipes are the standard Windows local IPC mechanism
2. Built-in security (ACL, SID validation, impersonation)
3. Protobuf provides efficient serialization with schema evolution
4. Both C++ (`protobuf`) and Dart (`protobuf` package) have mature support
5. MethodChannel cannot reach a separate process — FFI to named pipes is required

## Consequences

- Custom framing protocol (magic + length + payload); max payload **2 MB**
- Dart FFI on a dedicated **I/O isolate** (not UI isolate) — see ADR-008
- Explicit pipe **SDDL** required (see IPC doc)
- Protocol versioning required for compatibility
- Protobuf codegen step in build pipeline
- Live events delivered via **per-connection queues**, not a shared ring

## References

- [05 — IPC Design](../05-ipc.md)
- [03 — Flutter Architecture](../03-flutter-architecture.md)
- [ADR-008](ADR-008-hot-cold-live-queues.md)
- [CreateNamedPipe](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createnamedpipew)
