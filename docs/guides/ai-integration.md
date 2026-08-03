# Pulse AI Integration (MCP)

Pulse exposes a read-only [Model Context Protocol](https://modelcontextprotocol.io/) server (**PulseMCP**) so AI clients can observe Windows diagnostics through Pulse — without changing Windows.

## Principles

- **Opt-in.** MCP is disabled until you enable it in **Settings → AI Integration**.
- **Observation only.** Tools never inject, patch, or elevate silently.
- **Local-first.** Pulse does not upload data. Your AI client might — read its privacy policy.
- **Consent.** Pulse never edits Cursor/Claude config until you click **Register**.

## Requirements

- PulseService running
- PulseMCP installed (Setup installs `PulseMCP.exe` + private `runtime\` + `mcp\`)
- An MCP-capable client (Cursor, Claude Desktop; ChatGPT reserved)

End users do **not** need a system Node.js installation. The installer ships a private Node runtime used only by PulseMCP.

## Enable

1. Open **Settings → AI Integration**
2. Turn on **Enable Pulse MCP**
3. Optionally enable **Start Pulse MCP automatically with Pulse** (status heartbeat)
4. Under **AI clients**, click **Register** for Cursor (global) or Claude Desktop
5. Restart the AI client if it was already open

Policy file: `%LOCALAPPDATA%\Pulse\mcp\policy.json`

## Cursor (global)

Pulse writes `%USERPROFILE%\.cursor\mcp.json` and merges only the `pulse` server entry. Other MCP servers are left unchanged. A backup `*.pulse-backup-*` is created first.

On Windows, when the Pulse install path contains spaces (default: `C:\Program Files\Pulse\...`), registration uses a `cmd.exe /c` wrapper so Cursor does not split the path at the first space.

Unregister removes the Pulse entry **only if Pulse created it** (tracked in `%LOCALAPPDATA%\Pulse\mcp\client-registrations.json`).

## Claude Desktop

Same safety model for Claude config files (including the Windows `cmd.exe /c` wrapper when needed):

| Install | Config path |
|---------|-------------|
| Classic | `%APPDATA%\Claude\claude_desktop_config.json` |
| Microsoft Store / MSIX | `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json` |

**Register** writes both locations when present. Pulse itself is **not** distributed through the Microsoft Store — only Claude’s Store install affects the config path above.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `POLICY_DISABLED` | Enable Pulse MCP in Settings |
| Tools missing after upgrade | Re-Register; restart Cursor |
| `'C:\Program' is not recognized` | Re-Register after upgrading — install path spaces need `cmd.exe /c` wrapper |
| PulseMCP not found | Reinstall Pulse (Setup must include `PulseMCP.exe` + `runtime\`) |
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
