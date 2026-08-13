# AI Integration (Pulse MCP)

Pulse exposes Windows diagnostics to local AI coding tools through **PulseMCP.exe** — a first-class [Model Context Protocol](https://modelcontextprotocol.io/) server.

**Pulse uses the local MCP stdio transport. No remote MCP endpoint is required.**

Architecture: [33 — PulseMCP](../architecture/33-mcp-bridge.md) · [ADR-010](../architecture/decisions/ADR-010-mcp-first-class-product.md)

---

## Supported clients (local stdio)

| Client | Config path (Windows) | Top-level key |
|--------|----------------------|---------------|
| **Cursor** | `%USERPROFILE%\.cursor\mcp.json` | `mcpServers` |
| **Claude Desktop** | `%APPDATA%\Claude\claude_desktop_config.json` (+ Store Claude package path when present) | `mcpServers` |
| **Windsurf** | `%USERPROFILE%\.codeium\windsurf\mcp_config.json` | `mcpServers` |
| **Cline** | `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json` (and Insiders/VSCodium equivalents); optional CLI `%USERPROFILE%\.cline\mcp.json` | `mcpServers` |
| **VS Code / GitHub Copilot** | `%APPDATA%\Code\User\mcp.json` (user profile; also Insiders/VSCodium when present) | `servers` |

All of these launch the same **PulseMCP.exe** over **stdio**. PulseService remains the diagnostics source via named pipe IPC.

ChatGPT is **not** supported: it requires remote HTTP MCP, which Pulse does not expose.

---

## Prerequisites

- Pulse installed (or PulseMCP built from `apps/pulse_mcp`)
- **PulseService** running
- An MCP-capable local client from the table above
- In Pulse **Settings → AI Integration**: enable **Pulse MCP** (opt-in; default off)

---

## Register from Pulse

1. Open **Settings → AI Integration**
2. Enable **Pulse MCP**
3. Under **AI Tool Integrations**, click **Register** for each installed client
4. Restart the AI client so it reloads MCP config

**Consent.** Pulse never edits Cursor / Claude / Windsurf / Cline / VS Code config until you click **Register**.

On Windows, when the Pulse install path contains spaces (default: `C:\Program Files\Pulse\...`), registration uses a `cmd.exe /c` wrapper so clients do not split the path at the first space.

Registration:

- Backs up the target JSON first
- Writes **only** the `pulse` server entry
- Leaves every other MCP server untouched
- Is idempotent (re-register updates the Pulse entry)

**Unregister** removes only the Pulse entry, and only if Pulse created the registration marker.

If a client shows **Not installed**, detection did not find that product — you can still Register when a known config path exists (soft path), or install the client first.

---

## Manual config examples

### Cursor / Windsurf / Claude / Cline (`mcpServers`)

```json
{
  "mcpServers": {
    "pulse": {
      "command": "C:\\Program Files\\Pulse\\PulseMCP.exe",
      "args": [],
      "env": {}
    }
  }
}
```

With spaces (equivalent to Pulse’s Windows wrapper):

```json
{
  "mcpServers": {
    "pulse": {
      "command": "cmd.exe",
      "args": ["/c", "C:\\Program Files\\Pulse\\PulseMCP.exe"],
      "env": {}
    }
  }
}
```

### VS Code / GitHub Copilot (`servers`)

User profile `mcp.json` (Command Palette → **MCP: Open User Configuration**):

```json
{
  "servers": {
    "pulse": {
      "type": "stdio",
      "command": "C:\\Program Files\\Pulse\\PulseMCP.exe",
      "args": [],
      "env": {}
    }
  }
}
```

After registration, use Copilot **Agent** mode so tools from PulseMCP are available.

---

## Security

- PulseMCP runs as a **local child process** of the AI client
- Talks to PulseService only over the existing **named pipe**
- Policy-controlled (`%LOCALAPPDATA%\Pulse\mcp\policy.json`)
- Does **not** listen on HTTP, open a network port, or send telemetry
- Observation-only tools (no OS mutation)

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Tools missing after upgrade | Re-Register; restart the AI client |
| `POLICY_DISABLED` | Enable Pulse MCP in Settings |
| Service unavailable | Start PulseService |
| Invalid JSON in client config | Restore `*.pulse-backup-*` next to the config file |
| VS Code tools not visible | Confirm `servers` (not `mcpServers`) in user `mcp.json`; use Agent mode |

---

## Related

- [33 — PulseMCP architecture](../architecture/33-mcp-bridge.md)
- Settings UI: **AI Integration**
