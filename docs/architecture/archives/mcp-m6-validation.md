# PulseMCP M6 validation report

**Date:** 2026-08-02  
**PulseMCP version:** `0.6.0`  
**Pulse app/service stamp:** `0.2.1-beta` / service `0.2.0-beta`  
**Scope:** M6 — `report.export` (json / csv / html / pdf / markdown)  
**Status:** **FROZEN** — all required gates PASS. M7 blocked until explicit start.

## Validation gate

| Check | Required | Status |
|-------|----------|--------|
| `npm test` | Yes | **PASS** — 39/39 |
| `npm run validate:m6` | Yes | **PASS** — 14/14 |
| Cursor (production MCP client) | Yes | **PASS** — 2026-08-02T11:30Z |
| Export every supported format | Yes | **PASS** |
| Generated files open / parse | Yes | **PASS** — JSON parse, HTML doctype, PDF `%PDF` |
| Large reports | Yes | **PASS** — timeline limit=500 (~300 KB) |
| Concurrent exports | Yes | **PASS** — 3 parallel |
| Temp report cleanup | Yes | **PASS** — TTL store removes expired temps |
| Claude Desktop | Optional | Skipped |

## Implementation rules checklist

| Rule | Status |
|------|--------|
| Reuse snapshot IPC (no new collectors) | Pass — Health / Timeline / Diagnostics / Inventory Domain |
| No duplicate report pipeline in service | Pass — TypeScript writers in PulseMCP (Flutter ReportExporter parity) |
| Metadata only over MCP | Pass — never returns report body |
| Optional output path vs temp | Pass |
| Structured errors | Pass — `INVALID_REPORT_TYPE`, `INVALID_FORMAT`, `EXPORT_FAILED`, `ACCESS_DENIED`, `NOT_SUPPORTED` |
| `mcp.self` capabilities | Pass — `report.export` + `reportFormats` |
| Read-only Windows | Pass — writes only user export / temp dirs |

## Automated tests

```text
cd apps/pulse_mcp && npm test
```

**39/39** (writers + live export soft test including cleanup).

## Harness

```text
cd apps/pulse_mcp && npm run validate:m6
```

**14/14** — formats, large timeline, concurrent, temporary, error codes.

## Cursor — PASS

| Check | Result | Notes |
|-------|--------|-------|
| `mcp.self` | Pass | `0.6.0`, namespace `report`, `report.export` |
| `report.export` json/csv/html/pdf/md | Pass | metadata only |
| Temp export | Pass | `temporary: true` under `%TEMP%\Pulse\mcp-reports` |

## Sign-off

| Role | Required | Result |
|------|----------|--------|
| Automated | Yes | **PASS** |
| `validate:m6` | Yes | **PASS** |
| Cursor | Yes | **PASS** |
| Formats + files | Yes | **PASS** |
| Large / concurrent / cleanup | Yes | **PASS** |

**M6 freeze:** 2026-08-02.  
**M7:** do not start until this freeze and an explicit go-ahead.
