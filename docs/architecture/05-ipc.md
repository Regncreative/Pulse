# 05 — IPC Design

## Purpose

IPC between PulseApp and PulseService. **Never HTTP** (AGENTS.md).

---

## Transport

| Property | Value |
|----------|-------|
| Pipe | `\\.\pipe\PulseService` |
| Mode | Byte stream + app framing |
| Max instances | 4 |
| Max frame payload | **2 MB** (not 16 MB) |

Named pipes + Protobuf remain the locked choice ([ADR-003](decisions/ADR-003-named-pipe-ipc.md)).

---

## Pipe SDDL (Required)

Use an explicit SDDL when creating the pipe. v1 baseline:

```
D:(A;;GA;;;SY)(A;;GA;;;LS)(A;;GRGW;;;BA)(A;;GRGW;;;BU)
```

| ACE | Meaning |
|-----|---------|
| SY | SYSTEM — full |
| LS | LocalService — full |
| BA | Administrators — read/write |
| BU | Users — read/write (local interactive clients) |

**Rules:**

- Deny network logon classes if tightening later
- After connect: optional `ImpersonateNamedPipeClient` → read SID → `RevertToSelf` (never run work while impersonating)
- Test with a **standard (non-admin) user** before release

Refine SDDL only via ADR if lockdown environments require it.

---

## Framing

```
Magic 4 bytes "PULS" (0x50554C53) | Length uint32 LE | Protobuf Envelope
```

Reject frames over 2 MB; close connection.

---

## Envelope

Same envelope pattern as before (`ClientHello`, `ServerHello`, live subscribe, query range, get event, health, errors). Protocol version **1**.

Live pushes: `request_id = 0`, `LiveEventBatch` of **summaries** (Level 1 fields).

`GetEvent` returns Level 1+2; Level 3 included when available (lazy raw may be empty with `raw_pending` / fetch-on-demand semantics — see event model).

---

## Live Delivery (P0)

**Server side:** each accepted connection owns a **bounded live queue** (default capacity 1000 summaries).

- Ingest **never** writes the pipe; it only `try_push` to connection queues
- IPC worker drains queues and writes frames
- On overflow: drop oldest for **that** connection; increment `live_dropped`; surface in health / UI

**No shared ring consumer head.**

---

## Backpressure & Reconnect

| Condition | Behavior |
|-----------|----------|
| Slow client | Per-connection drops; ingest unaffected |
| Disconnect | Destroy connection queue |
| Reconnect | Gap fill via `QueryRange`, then `SubscribeLive` |

---

## Flutter Client

`PulseIpcClient` runs entirely on the **I/O isolate** ([03](03-flutter-architecture.md), [11](11-threading.md)).

---

## Related Documents

- [03 — Flutter](03-flutter-architecture.md)
- [07 — Timeline](07-timeline-engine.md)
- [ADR-008](decisions/ADR-008-hot-cold-live-queues.md)
