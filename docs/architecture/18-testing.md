# 18 — Testing Strategy

## Principles

- Fast, deterministic CI
- Golden fixtures for Event Log → PulseEvent Level 1/2
- No live ETW/kernel in CI
- No WMI indication tests in v1 CI
- No fabricated metrics in tests or fixtures

## CI (`.github/workflows/ci.yml`)

Runs on `push` to `master`/`main` and on pull requests:

| Job | Commands |
|-----|----------|
| **service** | CMake configure + Release build + `ctest -C Release` (all registered service tests) |
| **flutter** | `flutter analyze` + `flutter test` in `apps/pulse_app` |
| **pulse_mcp** | `npm ci` + `npm run build` + `npm test` in `apps/pulse_mcp` |

Service `ctest` targets today include `pulse_wire_tests`, `event_humanizer_tests`, `event_intelligence_tests`, and `ipc_client_thread_lifetime_test`. Optional IPC ping tools are build artifacts, not CI gates.

## Unit

- EventLogNormalizer + Enricher (embedded rules)
- Frame codec / wire tests
- MPSC / live queue drop behavior
- Dedup by channel+record_id
- Event humanizer + intelligence rules
- PulseMCP policy, framing, `mcp.self` (Vitest)

## Integration

- Pipe handshake
- SubscribeLive + QueryRange with fixture-backed store
- Slow-client live drop does not block writer/ingest (simulated)
- PulseMCP IPC hello/ping against a live PulseService (manual or local; not required in GitHub-hosted CI until a service fixture exists)

## Flutter

- Controllers with mock IPC
- Timeline shows Level 1 only
- I/O isolate boundary covered by unit/integration where practical

## Manual pre-release

- Service install, app connect, Application Error appears as human summary
- Detail Level 2 / expand Level 3
- Kill service → reconnect + gap fill
- Idle CPU near zero with Event Log only
- Multi-channel Timeline populates (not System-only)

## Related Documents

- [21 — Event Viewer Integration](21-event-viewer-integration.md)
- [33 — PulseMCP](33-mcp-bridge.md)
- [34 — Engineering roadmap](34-engineering-roadmap.md)
