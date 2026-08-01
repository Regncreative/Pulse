# Architecture Decision Records

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](ADR-001-cpp-backend.md) | C++20 Backend | Accepted |
| [ADR-002](ADR-002-windows-service.md) | Windows Service Process Model | Accepted |
| [ADR-003](ADR-003-named-pipe-ipc.md) | Named Pipe IPC with Protobuf | Accepted |
| [ADR-004](ADR-004-storage-strategy.md) | Hot Cache + Async SQLite (supersedes ring multi-reader) | Accepted |
| [ADR-005](ADR-005-source-priority.md) | Superseded by ADR-007 for v1 scope | Superseded |
| [ADR-006](ADR-006-plugin-deferral.md) | Plugin System Deferred | Accepted |
| [ADR-007](ADR-007-event-log-only-v1.md) | Event Log Only for Timeline v1 (Health ETW: see ADR-009) | Accepted |
| [ADR-008](ADR-008-hot-cold-live-queues.md) | Hot/Cold Path + Per-Connection Live Queues | Accepted |
| [ADR-009](ADR-009-health-network-etw.md) | Health per-process network via scoped ETW | Accepted |
| [ADR-010](ADR-010-mcp-first-class-product.md) | PulseMCP first-class MCP product | Accepted |

To change a locked decision, add a new ADR that references the original.
