# Upgrade notes (MCP)

- `%LOCALAPPDATA%\Pulse\mcp\policy.json` and `client-registrations.json` persist across upgrades
- After changing the install directory, **Unregister** then **Register** so launch paths update
- PulseMCP `0.7.0` adds status heartbeats and productization UI; tools/resources remain M2–M6 frozen
- Pipe max instances raised to **8** (rebuild/reinstall PulseService to pick up)
