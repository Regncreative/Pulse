# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| `0.1.0-beta.x` (pre-release) | Yes — best effort |
| Older / unsigned experimental builds | No |

Pulse is currently in **private / pre-public** development. Security reports are welcome from collaborators and will remain private until a fix is available.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Preferred channel (until a public security contact is published):

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
- Elevation only for explicit service install / uninstall

Reports that rely on social engineering, physical access, or already-compromised admin sessions may be closed as out of scope unless they reveal a Pulse-specific flaw.
