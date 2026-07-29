# Pulse

> See what Windows is really doing.

Read-only Windows diagnostics platform. **TASK-001 bootstrap** — architecture + IPC Ping/Pong only. No Event Log collection yet.

## Quick start

See [BUILD.md](BUILD.md), [DEVELOPMENT.md](DEVELOPMENT.md), and [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md).

Architecture: [docs/architecture/README.md](docs/architecture/README.md)

## Layout

| Path | Purpose |
|------|---------|
| `apps/pulse_app` | Flutter Desktop UI |
| `service/pulse_service` | Native Windows Service |
| `shared/` | Protocol + common headers |
| `tools/` | Scripts and IPC ping tool |
| `tests/` | Fixtures / future tests |
| `docs/` | Architecture documentation |
