# 04 — Native Windows Service

## Purpose

`PulseService` — C++20 Windows Service for **v1 Event Log collection** only.

---

## Service Identity

| Property | Value |
|----------|-------|
| Service name | `PulseService` |
| Display name | Pulse |
| Description | Read-only Windows Event Log collector for Pulse |
| Binary | `PulseService.exe` |
| Install | `%ProgramFiles%\Pulse\Service\` |
| Data | `%ProgramData%\Pulse\` |
| Account | `NT AUTHORITY\LocalService` |

---

## Why a Service

Observation continues when the UI is closed; SCM recovery; privilege centralization. See [ADR-002](decisions/ADR-002-windows-service.md).

---

## Startup Sequence (v1)

1. SCM `ServiceMain` / or `--console`
2. Logging + config
3. Storage (cache + SQLite writer thread)
4. Collector
5. EventLogAdapter (pull subscriptions)
6. IpcServer
7. `SERVICE_RUNNING`

Target: IPC ready within ~2 seconds.

### Shutdown

Stop IPC accepts → stop adapter → drain ingest → flush writer → close logs → `SERVICE_STOPPED`.

### Recovery

Restart on failure (5s / 30s / 60s) as previously specified.

---

## Configuration (v1)

`%ProgramData%\Pulse\config.json`:

```json
{
  "version": 1,
  "sources": {
    "event_log": {
      "enabled": true,
      "channels": ["System", "Application"]
    }
  },
  "storage": {
    "summary_cache_capacity": 10000,
    "sqlite_path": "%ProgramData%\\Pulse\\data\\pulse.db",
    "retention_days": 7,
    "store_raw": false
  },
  "ipc": {
    "pipe_name": "\\\\.\\pipe\\PulseService",
    "max_connections": 4,
    "live_queue_capacity": 1000
  },
  "logging": {
    "level": "info",
    "path": "%ProgramData%\\Pulse\\logs\\"
  }
}
```

No `etw` / `wmi` keys in v1 schema. Unknown keys ignored for forward compatibility.

---

## Debug Console Mode

`PulseService.exe --console` for development (same init path, no SCM).

---

## Install / Uninstall / Control

Admin elevation is required for install and service control. The Pulse UI may launch these via an explicit UAC prompt (`runas`) — never silently.

| Flag | Behavior |
|------|----------|
| `--install` | Create/update SCM service (auto-start, LocalService) |
| `--install-start` | Install/update, start, wait until RUNNING |
| `--start` | Start installed service; wait until RUNNING |
| `--stop` | Stop service; wait until STOPPED |
| `--restart` | Stop then start |
| `--status` | Print SCM state (`not_installed` / `stopped` / `start_pending` / `stop_pending` / `running` / `unknown`) — no admin |
| `--uninstall` | Stop + delete service (preserves ProgramData) |

The Flutter client queries SCM state without elevation and offers Start / Stop / Restart / Repair on Diagnostics and offline recovery screens (issues #5–#7).

---

## Security

- Pipe SDDL documented in [05 — IPC](05-ipc.md)
- Impersonate only to read client SID; always `RevertToSelf`
- No network code
- Config writable by Administrators

---

## Related Documents

- [01 — System Overview](01-system-overview.md)
- [05 — IPC](05-ipc.md)
- [21 — Event Viewer Integration](21-event-viewer-integration.md)
