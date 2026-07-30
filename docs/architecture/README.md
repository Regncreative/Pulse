# Pulse v1 Architecture

Professional architecture documentation for Pulse — a read-only Windows diagnostics platform.

**Status:** v1 design (documentation only; no production code)

**Windows baseline:** Windows 10 version 1809 (October 2018 Update) and later, Windows 11

**v1 objective:** Prove a stable end-to-end pipeline:

```
Windows Event Log → Collector → IPC → Timeline → Human-readable events
```

Priorities: **simplicity, responsiveness, maintainability** over feature count.

---

## What This Is

This folder is the single source of truth for Pulse technical decisions. Every future implementation must align with these documents and the product constitution in [AGENTS.md](../../AGENTS.md).

Each feature should answer: **"What is Windows doing right now?"**

---

## Reading Order

| # | Document | Topic |
|---|----------|-------|
| 01 | [System Overview](01-system-overview.md) | Processes, trust boundaries, v1 scope |
| 02 | [Module Boundaries](02-module-boundaries.md) | Collector modules, dependency rules |
| 03 | [Flutter Architecture](03-flutter-architecture.md) | UI layers, I/O isolate, timeline |
| 04 | [Native Service](04-native-service.md) | SCM lifecycle, accounts |
| 05 | [IPC Design](05-ipc.md) | Named pipes, Protobuf, SDDL |
| 06 | [Event Engine](06-event-engine.md) | Hot-path ingest (Event Log only) |
| 07 | [Timeline Engine](07-timeline-engine.md) | Queries, per-connection live queues |
| 08 | [Data Flow](08-data-flow.md) | End-to-end Event Log path |
| 09 | [Event Model](09-event-model.md) | Canonical `PulseEvent` |
| 10 | [Storage](10-storage.md) | Summary cache + async SQLite |
| 11 | [Threading](11-threading.md) | MPSC, pull adapter, I/O isolate |
| 12 | [Error Handling](12-error-handling.md) | Explain, recover, log |
| 13 | [Logging](13-logging.md) | Structured JSON logs |
| 14 | [Plugins (Future)](14-plugins-future.md) | Deferred — not in v1 |
| 15 | [Folder Structure](15-folder-structure.md) | Monorepo layout |
| 16 | [Build System](16-build-system.md) | CMake, Flutter, Protobuf |
| 17 | [Development Workflow](17-development-workflow.md) | Local run, commits |
| 18 | [Testing](18-testing.md) | Unit, integration, fixtures |
| 19 | [Windows APIs](19-windows-apis.md) | v1 API inventory |
| 20 | [ETW Integration](20-etw-integration.md) | **Future milestone** |
| 21 | [Event Viewer Integration](21-event-viewer-integration.md) | **v1 primary source** |
| 22 | [WMI Integration](22-wmi-integration.md) | **Future milestone** |
| 23 | [Architecture Review](23-architecture-review.md) | Review (P0s accepted) |
| 24 | [Health Metrics vs Task Manager](24-health-metrics-task-manager.md) | System Health counter alignment |
| 25 | [Beta Release Packaging](25-beta-release.md) | Portable zip + fresh-machine checklist |

**Architecture Decision Records:** [decisions/](decisions/)

---

## Locked v1 Decisions

| Area | Decision |
|------|----------|
| Backend | C++20 / MSVC |
| Process model | Windows Service + Flutter Desktop client |
| IPC | Named pipe `\\.\pipe\PulseService` + length-prefixed Protobuf |
| UI pipe I/O | Dedicated Dart **I/O isolate** (never sync FFI on UI isolate) |
| v1 data source | **Windows Event Log only** (Wevtapi pull) |
| Live delivery | **Per-connection queues** (no shared ring consumer head) |
| Persist | **Async SQLite writer** (hot path never waits on disk) |
| Level 3 raw | **Lazy** (not on critical path; optional on disk) |
| Enrichment rules | **Embedded defaults** + optional ProgramData overrides |
| ETW / WMI / Plugins | Documented as **future milestones** — not in v1 execution |

See [decisions/](decisions/) for ADRs (including ADR-007 / ADR-008).

---

## Non-Goals (v1)

- No ETW, WMI, or plugin runtime
- No cloud, login, telemetry, or analytics
- No process injection, hooks, patches, or security bypass
- No antivirus / cleaner / optimizer features
- No HTTP for local UI↔service communication
- No Analytic/Debug Event Log channel subscriptions (API limitation)
- No FTS5 requirement on day one (simple filters first; FTS optional later)

---

## Information Hierarchy

1. **Level 1 — Human:** "Windows restarted Explorer."
2. **Level 2 — Technical:** "explorer.exe crashed (Exception code 0xC0000005)."
3. **Level 3 — Raw:** Complete event XML (loaded on demand)

Never expose technical information first.

---

## Future Milestones (Not v1)

| Milestone | Scope |
|-----------|--------|
| M2 | ETW consumer (see [20](20-etw-integration.md)) |
| M3 | WMI indications (see [22](22-wmi-integration.md)) — no `WITHIN` process polling |
| M4 | Out-of-process plugins (see [14](14-plugins-future.md)) |
| Later | Timeline replay, export, registry/file/network engines |

---

## How to Use These Docs

**Before implementing:** Read 01–05, then 06–11, then [21 — Event Viewer](21-event-viewer-integration.md).

**When proposing a change:** Write a new ADR before changing locked decisions.
