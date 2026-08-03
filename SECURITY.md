# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| `1.0.x` (stable) | Yes |
| `0.3.2-beta.x` (pre-release) | Best effort (upgrade to 1.0.x recommended) |
| Older beta / unsigned experimental builds | No |

Pulse **1.0.0** is the current stable release. Security reports are welcome and will remain private until a fix is available.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Preferred channel:

1. Contact the repository owner via GitHub private channels / email associated with [Regncreative](https://github.com/Regncreative).
2. Include:
   - Pulse version (installer name or Settings / Diagnostics)
   - Windows version / build
   - Reproduction steps and impact
   - Whether the issue involves privilege escalation, IPC trust boundaries, or local data exposure

We aim to acknowledge reports within **7 days** and coordinate disclosure after a fix is ready.

## Scope notes

Pulse is **read-only** by design:

- No process injection, hooks, or kernel patching
- Local named-pipe IPC only (no cloud)
- Elevation only for explicit user actions: service install / uninstall / start / stop / restart (UAC)

Reports that rely on social engineering, physical access, or already-compromised admin sessions may be closed as out of scope unless they reveal a Pulse-specific flaw.
