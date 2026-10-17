# Pulse security and privacy

What Pulse can and cannot do on your PC, and what leaves it.

## Read-only by design

- Pulse **reads** Windows Event Logs, performance counters, hardware and software inventory, and per-process network statistics (ETW). It never changes Windows settings, services, drivers or files outside its own folders.
- No process injection, hooks, kernel drivers or patches.
- Only official Windows APIs.

## The PulseService background service

- Runs as **NT AUTHORITY\LocalService**, a low-privilege account, not as SYSTEM or an administrator.
- Talks to the Pulse app over a **local named pipe** (`\\.\pipe\PulseService`). The pipe accepts SYSTEM, LocalService, Administrators and local users on this PC; it is not reachable from the network. Pulse opens no network ports.
- Starting, stopping or restarting the service uses the Windows service permissions: it needs an administrator, so Pulse asks through the normal **UAC** prompt. Pulse never elevates on its own.

## What leaves your PC

By default, **nothing**. No telemetry, analytics, crash reports, accounts or cloud.

Only these features use the network, and only when you use them:

| Feature | What is sent | Where |
|---------|--------------|-------|
| **Assistant** (optional) | Your question and the diagnostics it needs | A local AI runtime on this PC (Ollama / LM Studio) at `127.0.0.1`. See below. |
| **Check for updates** (GitHub edition, optional) | An ordinary HTTPS request with Pulse's version in the User-Agent | `api.github.com`, only when you click *Check* or turn on weekly checks |

## Assistant: this PC only

Diagnostic data never leaves this PC, and there is no setting that changes that.

- The Assistant connects only to `127.0.0.1` or `::1`. Names such as `localhost` are refused, because the hosts file can point them at another machine.
- Settings → Privacy → Assistant lets you change the **port** of Ollama or LM Studio. There is no field for an address, so other computers on your network and cloud services cannot be configured.
- Redirects are never followed and system or environment proxies are ignored, so a local server cannot pass your data on.
- The optional **LM Studio API key** is kept in Windows Credential Manager (this PC only, not roaming). It is never written to settings, the settings export, logs, reports or diagnostics bundles. *Reset all settings* removes it.

## Exports and shared reports

- Reports, Timeline exports and diagnostics bundles are written to **Downloads\Pulse** (or a folder you choose). Nothing is uploaded.
- **Settings → Privacy → Mask personal details in exports** (on by default) replaces user and computer names, profile paths, account SIDs, e-mail, IP and MAC addresses and hardware serial numbers with tokens such as `[user]` before the file is written.

## Opening an .evtx from another PC

The file is read by `PulseService.exe --read-evtx` running as **you** (not as the service), never modified, and not uploaded. See [ADR-014](../architecture/decisions/ADR-014-open-exported-evtx.md).

## Code signing

Releases are not code-signed yet (a SignPath Foundation application is in review), so Windows SmartScreen or antivirus tools may warn. Verify downloads against the SHA-256 checksums on the release page. The Microsoft Store edition is signed by Microsoft.

## Reporting a vulnerability

See [SECURITY.md](../../SECURITY.md). Please do not open a public issue for security problems.
