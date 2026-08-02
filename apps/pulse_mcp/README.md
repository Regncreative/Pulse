# PulseMCP

First-class [Model Context Protocol](https://modelcontextprotocol.io/) server for Pulse.

Architecture: [docs/architecture/33-mcp-bridge.md](../../docs/architecture/33-mcp-bridge.md) · [ADR-010](../../docs/architecture/decisions/ADR-010-mcp-first-class-product.md)

## Status

| Milestone | State |
|-----------|--------|
| **M1** | Shipped — `mcp.self`, policy, hello/ping |
| **M2** | **Frozen** — `system.*` tools + `pulse://system/*` resources/subscriptions ([validation](../../docs/architecture/archives/mcp-m2-validation.md)) |
| M3–M7 | M3 next — `process.list` / `search` / `details` |

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
