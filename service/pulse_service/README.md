# PulseService

Native Windows service for Pulse — Event Log collection, named-pipe IPC, System Health sampling.

## CLI

```
PulseService.exe --console         Run interactively (dev)
PulseService.exe --install         Install/update service (admin)
PulseService.exe --install-start   Install, start, verify RUNNING (admin)
PulseService.exe --start           Start installed service (admin)
PulseService.exe --stop            Stop installed service (admin)
PulseService.exe --restart         Restart installed service (admin)
PulseService.exe --status          Print SCM state (no admin)
PulseService.exe --uninstall       Stop + delete service (admin)
PulseService.exe --version
PulseService.exe                   Run as SCM service
```

`--status` prints one of: `not_installed`, `stopped`, `start_pending`, `stop_pending`, `running`, `unknown`.

## Notes

- Observation only — no injection, hooks, or OS mutation.
- The Pulse app can start/stop/restart via elevated CLI after an explicit UAC prompt.
