# Pulse AI Integration (MCP)

Pulse exposes a read-only [Model Context Protocol](https://modelcontextprotocol.io/) server (**PulseMCP**) so AI clients can observe Windows diagnostics through Pulse — without changing Windows.

## Principles

- **Opt-in.** MCP is disabled until you enable it in **Settings → AI Integration**.
- **Observation only.** Tools never inject, patch, or elevate silently.
- **Local-first.** Pulse does not upload data. Your AI client might — read its privacy policy.
- **Consent.** Pulse never edits Cursor/Claude config until you click **Register**.

## Requirements

- PulseService running
- PulseMCP installed (Setup installs `PulseMCP.cmd` + `mcp\`)
- [Node.js 20+](https://nodejs.org/) on `PATH` (launcher uses `node`)
- An MCP-capable client (Cursor, Claude Desktop; ChatGPT reserved)

## Enable

1. Open **Settings → AI Integration**
2. Turn on **Enable Pulse MCP**
3. Optionally enable **Start Pulse MCP automatically with Pulse** (status heartbeat)
4. Under **AI clients**, click **Register** for Cursor (global) or Claude Desktop
5. Restart the AI client if it was already open

Policy file: `%LOCALAPPDATA%\Pulse\mcp\policy.json`

## Cursor (global)

Pulse writes `%USERPROFILE%\.cursor\mcp.json` and merges only the `pulse` server entry. Other MCP servers are left unchanged. A backup `*.pulse-backup-*` is created first.

Unregister removes the Pulse entry **only if Pulse created it** (tracked in `%LOCALAPPDATA%\Pulse\mcp\client-registrations.json`).

## Claude Desktop

Same safety model for `%APPDATA%\Claude\claude_desktop_config.json`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `POLICY_DISABLED` | Enable Pulse MCP in Settings |
| Tools missing after upgrade | Re-Register; restart Cursor |
| PulseMCP not found | Reinstall Pulse; ensure Node.js on PATH |
| Invalid JSON in Cursor config | Restore `mcp.json.pulse-backup-*` |
| Service pipe offline | Start PulseService from Diagnostics |

Logs: `%LOCALAPPDATA%\Pulse\logs\pulsemcp\`

## Security

- Config edits require an explicit Register / Unregister click
- Backups before write
- JSON validated before replace
- Uninstall runs `--cleanup-registrations` for Pulse-owned entries only

## Upgrade notes

- Policy and registration markers survive app upgrades under `%LOCALAPPDATA%\Pulse\mcp\`
- Re-register after moving the install directory so the launch command path stays correct
