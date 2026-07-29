# IMPLEMENTATION_GUIDE

## Current milestone: TASK-001 Bootstrap

**In scope**

- Repository layout
- Flutter shell (timeline / settings / diagnostics placeholders)
- Windows Service lifecycle (`--console`, `--install`, `--uninstall`)
- Named-pipe IPC with Protobuf-compatible framing
- ClientHello / ServerHello, Ping / Pong, Heartbeat
- Per-connection queue structures (server)
- Flutter I/O isolate for pipe I/O
- Logging, config placeholder, CMake, CI skeleton

**Out of scope**

- Event Log / Wevtapi collection
- ETW / WMI
- Timeline business logic
- SQLite persistence of events
- Enrichment rules runtime

## End-to-end validation path

1. Build `PulseService.exe`
2. Run `PulseService.exe --console`
3. Run `pulse_ipc_ping.exe` **or** Flutter Diagnostics → Ping
4. Observe Pong
5. Ctrl+C service — clean shutdown

## Next implementation tasks (not this milestone)

1. Event Log pull adapter (doc 21)
2. Collector hot path + async SQLite writer (ADR-008)
3. Live event batches to UI
4. Timeline Level 1 rendering

Follow ADRs 007 and 008 strictly.
