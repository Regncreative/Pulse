# Troubleshooting

## Pulse offline

- Start PulseService from **Diagnostics → Service**
- Confirm `\\.\pipe\PulseService` is not blocked by third-party security tools

## MCP tools return POLICY_DISABLED

Enable **Settings → AI Integration → Enable Pulse MCP**.

## Cursor does not list Pulse tools

1. Register again (global `~\.cursor\mcp.json`)
2. Fully quit Cursor and reopen
3. Confirm `PulseMCP.exe` runs: it should start and wait on stdio for an MCP client (Ctrl+C to stop)

## Invalid mcp.json after Register

Restore the newest `mcp.json.pulse-backup-*` next to the config file, then retry Register.

## PulseMCP / bundled runtime missing

Reinstall Pulse with the official Setup. Pulse ships a private Node runtime under `runtime\` — a system Node.js install is not required and is not used by the production launcher.
