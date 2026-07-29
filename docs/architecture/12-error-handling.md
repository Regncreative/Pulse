# 12 — Error Handling

## Purpose

Every error must **explain**, **recover**, and **log**. Never silent failure.

---

## Categories (v1)

| Category | User-visible | Example |
|----------|--------------|---------|
| `ADAPTER_ERROR` | Yes | Event Log subscription failed |
| `PARSE_ERROR` | Event flagged | Normalization failed |
| `STORAGE_ERROR` | Yes if durable path fails | Disk full / SQLite error |
| `IPC_ERROR` | Yes | Service not running / pipe ended |
| `CONFIG_ERROR` | Yes | Unknown channel |
| `INTERNAL_ERROR` | Yes (generic + detail) | Unexpected |

No ETW/WMI capability errors in v1 UI.

---

## Contracts

### EventLogAdapter

- Access denied / missing channel: status + retry/backoff; do not crash service
- Pull loop errors: log, reconnect subscription

### Collector / ingest

- Parse failures: `parse_error` event; continue
- Live queue overflow: drop per connection; counter; UI can show “events dropped”
- Writer failure: hot path continues

### IPC / App

- Service down: human StatusBar message
- Protocol mismatch: `INCOMPATIBLE_VERSION`
- Reconnect with backoff + gap fill

### UI hierarchy

Level 1 human message → expandable Level 2 technical → no HRESULT in primary UI.

---

## Related Documents

- [13 — Logging](13-logging.md)
- [05 — IPC](05-ipc.md)
