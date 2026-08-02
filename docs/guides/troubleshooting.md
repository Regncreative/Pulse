# Troubleshooting

## Pulse offline

- Start PulseService from **Diagnostics → Service**
- Confirm `\\.\pipe\PulseService` is not blocked by third-party security tools

## MCP tools return POLICY_DISABLED

Enable **Settings → AI Integration → Enable Pulse MCP**.

## Cursor does not list Pulse tools

1. Register again (global `~\.cursor\mcp.json`)
2. Fully quit Cursor and reopen
3. Confirm `PulseMCP.cmd` runs: `PulseMCP.cmd` should start (stdio waits for a client)

## Invalid mcp.json after Register

Restore the newest `mcp.json.pulse-backup-*` next to the config file, then retry Register.

## Node not found

Install Node.js 20+ and ensure `node` is on PATH for the user account that runs Cursor.
