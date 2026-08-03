# 40 — Portable ZIP vs Windows Service

## Purpose

Clarify packaging modes for operators and close the “true portable” expectation gap.

## Short answer

**PulseService is required** for a working Pulse session (Timeline, live Event Log, System Health collectors). The Flutter UI (`Pulse.exe`) is a client; observation runs in the native Windows service.

A **ZIP / folder payload** is a convenient copy of binaries. It is **not** a true portable edition: the service must still be registered with SCM (admin / UAC) and started. Unzipping alone does not replace install.

For **stable releases**, recommend the **service-required** path: Inno Setup (`Pulse-Setup-*.exe`) or elevated `PulseService.exe --install-start` from the payload folder.

## Why the service is required

| Need | Why a service |
|------|----------------|
| Continuous observation | Collector survives UI close and user logoff |
| SCM recovery | Automatic restart after crashes |
| Privilege model | Centralized, minimal `LocalService` account |
| Architecture | ADR-002 process model |

See [ADR-002](decisions/ADR-002-windows-service.md) and [04 — Native Service](04-native-service.md).

## Packaging modes

| Artifact | Role |
|----------|------|
| `Pulse-Setup-*-windows-x64.exe` | **Recommended** — installs runtime deps, registers/starts PulseService, launches UI ([25 — Beta packaging](25-beta-release.md)) |
| `dist/Pulse/` or ZIP of that tree | Developer / advanced payload — same binaries; **still requires** elevated `--install-start` |
| `PulseService.exe --console` | Dev foreground only — not a portable product mode |

## FAQ

**Can I run Pulse from a USB stick with no install?**  
No. Named-pipe IPC and Event Log collection need PulseService registered and running. Copying the ZIP does not make a portable product.

**Is the ZIP “portable Pulse”?**  
No. It is an optional archive of the same install payload. Treat it as advanced packaging, not a separate product SKU.

**Will there be a true portable SKU later?**  
Out of scope for v1.0. Any future portable mode would need an explicit architecture decision; do not assume the ZIP is that mode.

## Related

- [ADR-002 — Windows Service](decisions/ADR-002-windows-service.md)
- [04 — Native Service](04-native-service.md)
- [25 — Beta Release Packaging](25-beta-release.md)
- [Installation guide](../guides/installation.md)
