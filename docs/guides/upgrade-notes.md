# Upgrade notes (MCP)

- `%LOCALAPPDATA%\Pulse\mcp\policy.json` and `client-registrations.json` persist across upgrades
- After changing the install directory, **Unregister** then **Register** so launch paths update
- PulseMCP `0.7.1` ships `PulseMCP.exe` + a private Node runtime — **no system Node.js**. Re-Register after upgrading from **0.3.0-beta** so Cursor points at `PulseMCP.exe` instead of the old PATH-based `.cmd`
- Pipe max instances raised to **8** (rebuild/reinstall PulseService to pick up)
