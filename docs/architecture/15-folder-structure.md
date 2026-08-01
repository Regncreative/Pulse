# 15 — Folder Structure

## Repository (v1)

```
Pulse/
├── AGENTS.md
├── docs/architecture/          # This package
├── apps/pulse_app/             # Flutter UI
├── apps/pulse_mcp/             # PulseMCP.exe (official MCP server) — see 33-mcp-bridge.md
├── service/pulse_service/      # C++ service (Event Log only)
├── shared/pulse_protocol/      # Protobuf
├── tools/codegen/
└── tests/
```

## Service source (v1 — no ETW/WMI trees)

```
service/pulse_service/src/
├── main.cpp
├── service_core/
├── ipc/
├── collector/           # ingest + query facade
├── adapters/
│   └── event_log_adapter.*
├── storage/
├── logging/
└── util/
```

**Do not create** `etw_adapter`, `wmi_adapter`, or `plugin_*` source trees in v1.

Enrichment default rules: embedded resources under `collector/enrichment_rules/` (shipped in binary).

## App

Unchanged layered `lib/` layout; `ipc/` must document I/O isolate usage.

## Related Documents

- [16 — Build System](16-build-system.md)
