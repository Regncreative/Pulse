# Upgrade notes (MCP)

- `%LOCALAPPDATA%\Pulse\mcp\policy.json` and `client-registrations.json` persist across upgrades
- After changing the install directory, **Unregister** then **Register** so launch paths update
- PulseMCP `0.7.2` (in **0.3.2-beta**):
  - Wire tool names use underscores (`system_cpu`) for Claude Desktop compatibility
  - Microsoft Store Claude config path is registered alongside classic `%APPDATA%\Claude\...`
  - Re-Register + fully restart Claude/Cursor after upgrade
- PulseMCP `0.7.1` ships `PulseMCP.exe` + a private Node runtime — **no system Node.js**. Re-Register after upgrading from **0.3.0-beta** so Cursor points at `PulseMCP.exe` instead of the old PATH-based `.cmd`
- On Windows, Register writes a `cmd.exe /c` wrapper when the install path has spaces (`C:\Program Files\...`). Re-Register after upgrading if you see `'C:\Program' is not recognized`
- PulseService named-pipe max instances raised to **32** (config key `max_pipe_instances`). Restart/reinstall the service after upgrade or PulseMCP may log `IPC timeout connecting to PulseService` while the UI still looks online
- Pipe max instances raised to **8** in earlier M7 builds (superseded by 32)
