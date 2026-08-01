# PulseMCP

First-class [Model Context Protocol](https://modelcontextprotocol.io/) server for Pulse.

Architecture: [docs/architecture/33-mcp-bridge.md](../../docs/architecture/33-mcp-bridge.md) · [ADR-010](../../docs/architecture/decisions/ADR-010-mcp-first-class-product.md)

## M1 scope

- stdio MCP server (`@modelcontextprotocol/sdk`)
- Tool: `mcp.self` (versions, capabilities, diagnostics)
- Policy gate (`%LOCALAPPDATA%\Pulse\mcp\policy.json` or `PULSE_MCP_ENABLED`)
- IPC ClientHello / Ping against `\\.\pipe\PulseService`

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
