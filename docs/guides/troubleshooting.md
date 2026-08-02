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

## Cursor / Claude fail with `'C:\Program' is not recognized`

The install path contains spaces (`Program Files`). Older registrations pointed at an unquoted command. **Unregister** then **Register** again from **Settings → AI Integration**, then fully restart the AI client.

## PulseMCP: `IPC timeout connecting to PulseService`

Named-pipe slots were exhausted (`CreateFile` Win32 **231** / `ERROR_PIPE_BUSY`). Pulse UI can still work on an existing connection while new PulseMCP clients cannot connect.

1. Confirm PulseService is **Running**
2. Restart PulseService (Diagnostics → Service, or reinstall Setup)
3. Ensure the service binary reports `Listening on named pipe (max_instances=32)` in `%ProgramData%\Pulse\logs\`
4. Confirm `%ProgramData%\Pulse\config.json` has `"max_pipe_instances": 32` (legacy `"max_connections": 4` is too low for MCP)

Pipe name must be `\\.\pipe\PulseService` on both sides (unchanged).

## Claude chat error: `FrontendRemoteMcpToolDefinition.name` / pattern `^[a-zA-Z0-9_-]{1,64}$`

Claude Desktop rejects MCP tool names that contain dots. PulseMCP wire names use underscores (`system_cpu`, not `system.cpu`). Restart Claude after upgrading PulseMCP so it reloads `tools/list`.

## Claude Desktop shows "No servers added"

Microsoft Store Claude reads a different file than the classic install:

- Store: `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json`
- Classic: `%APPDATA%\Claude\claude_desktop_config.json`

Pulse Register now writes both. After Register, fully quit Claude (all windows) and reopen.
