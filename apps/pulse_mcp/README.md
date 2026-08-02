# PulseMCP

First-class [Model Context Protocol](https://modelcontextprotocol.io/) server for Pulse.

Architecture: [docs/architecture/33-mcp-bridge.md](../../docs/architecture/33-mcp-bridge.md) · [ADR-010](../../docs/architecture/decisions/ADR-010-mcp-first-class-product.md)

## Status

| Milestone | State |
|-----------|--------|
| **M1** | Shipped — `mcp.self`, policy, hello/ping |
| **M2** | **Frozen** — `system.*` tools + `pulse://system/*` ([validation](../../docs/architecture/archives/mcp-m2-validation.md)) |
| **M3** | **Frozen** — `process.list` / `process.search` / `process.details` ([validation](../../docs/architecture/archives/mcp-m3-validation.md)) |
| **M4** | **Frozen** — `timeline.list` / `timeline.search` + `pulse://timeline/live` ([validation](../../docs/architecture/archives/mcp-m4-validation.md)) |
| M5–M7 | Not started (gated on M4 freeze) |

## M2 tools

| Tool | Source |
|------|--------|
| `mcp.self` | Versions, namespaces, capabilities |
| `system.health` | Health Engine snapshot (optional `sections`) |
| `system.cpu` | Cached Health sample |
| `system.memory` | Cached Health sample |
| `system.gpu` | Cached Health sample (primary adapter) |
| `system.storage` | Volumes + disks from Health |
| `system.network` | Cached Health sample |

## M3 tools

| Tool | Source |
|------|--------|
| `process.list` | Health process inventory (filter/sort/paginate) |
| `process.search` | Same + required `query` |
| `process.details` | `GetProcessDetails` (cmdline redacted) |

Stable id = `pid` + `createTime` when known. Inventory fields absent on the wire (`signed`, `hasWindow`, …) return `null` + `unavailable`.

## M4 tools

| Tool | Source |
|------|--------|
| `timeline.list` | `GetTimelineSnapshot` (diagnostics channel set) |
| `timeline.search` | Snapshot + Flutter-aligned client filters |

`includeRaw` defaults **false**. Explicit Security channel requests return `ACCESS_DENIED` when the service account cannot open the Security log (`securityChannelAvailable` reports probe result).

## M4 resources (subscribable)

- `pulse://timeline/live` — `StartLiveMonitoring` while subscribed

## M2 resources (subscribable)

- `pulse://system/cpu`
- `pulse://system/memory`
- `pulse://system/gpu`
- `pulse://system/network`
- `pulse://system/health`

Health monitoring IPC (`StartHealthMonitoring`) runs **only** while at least one MCP client is subscribed. Tools reuse the latest cached sample when fresh — no polling loops, no duplicate collectors.

## Rules

- Structured JSON only (no markdown/prose tool bodies)
- Timestamps ISO-8601 UTC
- Errors: `SERVICE_UNAVAILABLE`, `TIMEOUT`, `POLICY_DISABLED`, `INVALID_ARGUMENT`, `NOT_SUPPORTED`, `ACCESS_DENIED`, `INTERNAL_ERROR`
- Single persistent IPC session per process

## Dev

```bash
cd apps/pulse_mcp
npm install
npm test
npm run build
# Enable policy for live use:
# set PULSE_MCP_ENABLED=true
npm start
```

## Client config

```json
{
  "mcpServers": {
    "pulse": {
      "command": "node",
      "args": ["C:/path/to/Pulse/apps/pulse_mcp/dist/main.js"],
      "env": { "PULSE_MCP_ENABLED": "true" }
    }
  }
}
```

PulseService must be running. Validation checklist: [docs/architecture/archives/mcp-m2-validation.md](../../docs/architecture/archives/mcp-m2-validation.md).
