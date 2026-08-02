# Pulse installation

## Recommended

1. Download `Pulse-Setup-<version>-windows-x64.exe`
2. Run the Setup (UAC). It installs Visual C++ runtime, registers PulseService, and launches Pulse.
3. Open **Settings → AI Integration** if you want MCP for AI clients.

## Portable payload

Advanced users can use the `dist\Pulse\` folder (or ZIP of that tree) from packaging:

- `Pulse.exe` — UI
- `service\PulseService.exe --install-start` (elevated) — **required**; unzip alone is not enough
- `PulseMCP.exe` — MCP server (bundled private Node runtime; no system Node.js)
- `PulseMCP.cmd` — compatibility launcher (same private runtime)

This is **not** a true portable edition. PulseService must be registered with Windows (SCM). Prefer the Setup installer for beta/post-beta. Details: [40 — Portable ZIP vs Windows Service](../architecture/40-portable-vs-service.md).

## Uninstall

Use Windows Apps & features / the Start menu Uninstall entry. Uninstall:

- Stops and removes PulseService
- Runs PulseMCP `--cleanup-registrations` for Pulse-created AI client entries only
- Leaves `%LOCALAPPDATA%\Pulse\` logs/policy unless you delete them manually
