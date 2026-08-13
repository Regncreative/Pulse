# ADR-010: PulseMCP as a First-Class Product Component

**Status:** Accepted — M1 shipped (`apps/pulse_mcp`: stdio, `mcp.self`, policy gate, IPC hello); M2+ per doc 33 / roadmap R5–R7

**Date:** 2026-08-01

**Supersedes:** Informal “MCP bridge” sketch from the UX redesign discussion — MCP is not a thin adapter; it is a peer product binary.

---

## Context

Pulse is a three-layer Windows observability platform:

| Binary | Role today |
|--------|------------|
| `Pulse.exe` | Flutter UI |
| `PulseService.exe` | Windows collectors + named-pipe IPC server |

External AI assistants (Claude Desktop, Cursor, Windsurf, Cline, VS Code / GitHub Copilot, and other **local stdio** MCP clients) should consume Pulse diagnostics **without** embedding an LLM or vendor API keys inside Pulse. Remote HTTP MCP (e.g. ChatGPT connectors) is out of scope for the local stdio product.

The [Model Context Protocol](https://modelcontextprotocol.io/specification/2025-11-25/) defines JSON-RPC over **stdio** and **Streamable HTTP**. Pulse must implement MCP **exactly** via an official SDK — no custom AI protocol.

Additional product requirements (approved):

1. PulseMCP is a **first-class** component (own version, health, logging, diagnostics).
2. Namespaced tools (`system.health`, `process.list`, …).
3. Structured JSON responses only (no pre-formatted prose).
4. MCP **Resources** + **subscriptions** for live health/timeline (avoid 1 Hz polling).
5. Rich tool metadata (latency, permissions, schemas, filters, examples).
6. Searchable timeline and filtered process list.
7. Reports generated **by Pulse**, not by the model (`report.export`).
8. In-app MCP Diagnostics section in Flutter.
9. Permission levels; v1 = Observation only.
10. Compatible with future Resources/Prompts/Sampling/HTTP/Auth without redesign.

## Decision

### Process model

Introduce a third peer binary:

```
Pulse.exe          — UI (Flutter)
PulseService.exe   — Collectors + IPC server (C++)
PulseMCP.exe       — Official MCP server (TypeScript SDK → packaged EXE)
```

All three have **independent**:

- Version strings (semver / marketing version)
- Health / readiness state
- Structured logging
- Diagnostics surfaces

```
AI MCP client
    │  MCP JSON-RPC (stdio v1; Streamable HTTP optional later)
    ▼
PulseMCP.exe
    │  existing Pulse IPC (\\.\pipe\PulseService, PULS frames)
    ▼
PulseService.exe
    │
    ▼
Windows APIs
```

Flutter connects to PulseMCP for **MCP Diagnostics UI** only (local status channel — see doc 33), not for tool execution on behalf of remote models.

### Protocol boundaries (locked)

| Boundary | Protocol | Notes |
|----------|----------|-------|
| Flutter ↔ PulseService | Named pipe + Protobuf | Unchanged; AGENTS.md “no HTTP” |
| PulseMCP ↔ PulseService | Same named pipe + Protobuf | PulseMCP is another pipe client |
| AI client ↔ PulseMCP | **Official MCP only** | stdio required; Streamable HTTP later |
| Pulse ↔ cloud LLMs | **None** | No API keys; no embedded models |

### Placement alternatives (rejected)

| Option | Why rejected |
|--------|----------------|
| MCP inside PulseService | stdio unfit for SCM service; mixes AI surface into collectors; hard to use official SDK |
| MCP inside Flutter | Clients must spawn MCP as a subprocess; UI must not be required; stdout conflict |

### Tool surface (v1)

Namespaced, Observation-permission tools only. Full catalog in [33-mcp-bridge.md](../33-mcp-bridge.md).

Write / Administrative tools (e.g. `process.kill`) are **schema-reserved** but **not registered** in v1.

### Data shape

Every tool returns **structured JSON** matching a published JSON Schema. Formatting for humans is the AI client’s job.

### Compatibility & discovery (normative — see doc 33)

PulseMCP must expose through `mcp.self`:

- MCP **protocol** version (negotiated / supported)
- **PulseMCP** server version
- **Pulse** (UI/product) version stamp when known
- **PulseService** version (from IPC hello/pong)
- **IPC** protocol version

Plus **capability discovery**: supported tools, resources, subscriptions, report formats, permissions, and protocol features so clients can adapt without hard-coding.

### Stable IDs, pagination, filtering

Domain objects use **stable identifiers** (pid+createTime, adapter LUID, interface GUID, event GUID, device id) — never display names alone. Collection tools support `limit` / `offset` / `cursor` and documented filters. Default page sizes are bounded; never dump thousands of rows.

### Resource lifecycle

Resources publish on documented cadences (e.g. CPU ~1 Hz, timeline event-driven, diagnostics on change). **Do not** publish unchanged payloads.

### Errors & timestamps

Failures are structured JSON (`ok: false`, `code`, `message`, `details`) — never plain-text-only failures. Every response includes `observedAt` (data time) and `generatedAt` (response build time).

### Backward compatibility

Tool names and response schemas are **additive-only**. Incompatible changes require a new MCP/API protocol version — never silent renames.

### Testing

Every implemented tool requires unit tests, IPC integration tests (live PulseService when available), and MCP integration tests.

### Live data

Expose MCP **Resources** with subscription support for CPU, Memory, GPU, Network, and Timeline so clients need not poll `system.*` every second.

### Reports

`report.export` generates files on disk (JSON / HTML / PDF / Markdown / CSV) using Pulse-owned formatters fed by IPC snapshots. The tool returns paths and metadata — never asks the model to invent report content.

### IPC changes

- **No** Envelope redesign for v1 tools that map to existing RPCs.
- Raise pipe max instances (4 → **8**) so UI + MCP + diagnostics clients coexist ([constants](../../../shared/pulse_common/include/pulse/constants.hpp)).
- Full Windows Services catalog remains **out of scope** until a future Inventory Engine; `service.status` v1 = PulseService identity/SCM only.

## Consequences

### Positive

- Claude / Cursor / Windsurf / Cline / VS Code (Copilot Agent) work via local stdio MCP config.
- Clear blast radius: MCP crashes do not take down collectors or UI.
- Official SDK tracks MCP evolution (Resources, Prompts, Sampling, HTTP, Auth).
- Aligns with AGENTS.md: observation only, local-first, no telemetry from Pulse itself.

### Negative / costs

- Third binary in installer and release matrix.
- PulseMCP needs PulseService running; tools return structured `service_unavailable` errors otherwise.
- Privacy: once a user enables MCP, the **AI host** may send tool/resource payloads to its cloud — Pulse must disclose this in Settings.

### Follow-ups

- Document 33 is the normative MCP API surface.
- Implementation is phased (33 §15; engineering roadmap R5–R7). M1 is complete; do not expand the tool surface without matching roadmap milestones.

## References

- [MCP Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [05-ipc.md](../05-ipc.md), [ADR-003](ADR-003-named-pipe-ipc.md)
- [AGENTS.md](../../../AGENTS.md)
- [33-mcp-bridge.md](../33-mcp-bridge.md)
