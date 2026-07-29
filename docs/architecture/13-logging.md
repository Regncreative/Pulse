# 13 — Logging Strategy

## Purpose

Structured JSON logs; no sensitive data; local only.

---

## Locations

| Component | Path |
|-----------|------|
| Service | `%ProgramData%\Pulse\logs\pulse-service-YYYY-MM-DD.jsonl` |
| App | `%LOCALAPPDATA%\Pulse\logs\pulse-app-YYYY-MM-DD.jsonl` |

## Schema

`timestamp`, `level`, `component`, `message`, optional `context`, `error_code`, `duration_ms`.

Levels: debug, info, warn, error, fatal. Default production: info.

## v1 Components

`ServiceCore`, `EventLogAdapter`, `Collector`, `Storage`, `IpcServer`, `PulseApp`.

No `EtwAdapter` / `WmiAdapter` loggers in v1 builds.

## Redaction

Never log secrets, full sensitive command lines, or Level 3 XML dumps in routine logs. Prefer `event_id` references.

## Rotation

Daily; retain ~14 days; size caps as before.

---

## Related Documents

- [12 — Error Handling](12-error-handling.md)
