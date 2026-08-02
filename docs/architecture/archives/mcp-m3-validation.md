# PulseMCP M3 validation report

**Date:** 2026-08-02  
**PulseMCP version:** `0.3.0`  
**Pulse app/service stamp:** `0.2.1-beta` / service `0.2.0-beta`  
**Scope:** M3 — `process.list`, `process.search`, `process.details`  
**Status:** **FROZEN** — all required gates PASS. M4 blocked until next milestone gate.

## Validation gate

| Check | Required | Status |
|-------|----------|--------|
| `npm test` | Yes | **PASS** — 24/24 |
| `npm run validate:m3` | Yes | **PASS** — 13/13 |
| Cursor (production MCP client) | Yes | **PASS** — 2026-08-02T11:08Z |
| Claude Desktop | Optional | Skipped |

## Implementation rules checklist

| Rule | Status |
|------|--------|
| No duplicate collectors / no polling | Pass — inventory from HealthUpdate stream only |
| Single persistent IPC session | Pass — shared `IpcSession` |
| Monitoring hold for inventory tools | Pass — `HealthCache.withInventory` refcount with resource subscribers |
| Structured JSON only | Pass |
| Stable id = `pid` + `createTime` | Pass |
| Null + `unavailable` for missing wire fields | Pass (`signed`, `hasWindow`, company on list, …) |
| Cmdline redaction | Pass — secret-like tokens → `***` |
| `PROCESS_NOT_FOUND` | Pass |
| `mcp.self` capabilities include `process.*` + namespace `process` | Pass |

## Automated tests

```text
cd apps/pulse_mcp && npm test
```

**24/24** green (includes `process.mappers` + live IPC soft tests).

## Harness

```text
cd apps/pulse_mcp && npm run validate:m3
```

**13/13** — listTools, mcp.self capabilities, list/search/details, PROCESS_NOT_FOUND.

## Cursor (required) — PASS

Server: `project-0-Pulse-pulse` @ `mcpServer` **0.3.0**.

| Check | Result | Notes |
|-------|--------|-------|
| `mcp.self` | Pass | namespaces include `process`; tools include all three |
| `process.list` | Pass | count=15, truncated, stable ids, ISO timestamps |
| `process.search` | Pass | query=`Pulse` → PulseService.exe |
| `process.details` | Pass | pid=26352 PulseService; parent/user/integrity/elevated |
| `PROCESS_NOT_FOUND` | Pass | pid=2147483646 |

## Honesty notes (not defects)

- List/search rows: `company`, `description`, `signed`, `hasWindow`, `integrity` are `null` with `unavailable` reasons — not on `HealthProcessEntry` wire.
- `company` / `signed` filters are ignored and listed in `filtersIgnored` (no inventory fields to match).
- `process.details` cmdline may be `null` when the service cannot read it (`unavailable.commandLine`).

## Sign-off

| Role | Required | Result |
|------|----------|--------|
| Automated (vitest) | Yes | **PASS** |
| Harness `validate:m3` | Yes | **PASS** |
| Cursor | Yes | **PASS** |
| Claude Desktop | No | Skipped |

**M3 freeze:** 2026-08-02.  
**M4:** blocked until M3 frozen (this report) and explicit start.
