# 18 — Testing Strategy

## Principles

- Fast, deterministic CI
- Golden fixtures for Event Log → PulseEvent Level 1/2
- No live ETW/kernel in CI
- No WMI indication tests in v1 CI

## Unit

- EventLogNormalizer + Enricher (embedded rules)
- Frame codec
- MPSC / live queue drop behavior
- Dedup by channel+record_id

## Integration

- Pipe handshake
- SubscribeLive + QueryRange with fixture-backed store
- Slow-client live drop does not block writer/ingest (simulated)

## Flutter

- Controllers with mock IPC
- Timeline shows Level 1 only
- I/O isolate boundary covered by unit/integration where practical

## Manual pre-release

- Service install, app connect, Application Error appears as human summary
- Detail Level 2 / expand Level 3
- Kill service → reconnect + gap fill
- Idle CPU near zero with Event Log only

## Related Documents

- [21 — Event Viewer Integration](21-event-viewer-integration.md)
