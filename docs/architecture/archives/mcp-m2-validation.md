# PulseMCP M2 validation report

**Date:** 2026-08-02  
**PulseMCP version:** `0.2.0`  
**Pulse app/service stamp:** `0.2.1-beta` / service `0.2.0-beta`  
**Scope:** M2 — `system.*` tools + `pulse://system/*` resources/subscriptions  
**Status:** **FROZEN** — all required gates PASS. M3 unblocked.

## Validation gate

| Check | Required | Status |
|-------|----------|--------|
| `npm test` | Yes | **PASS** — 19/19 |
| `npm run validate:m2` | Yes | **PASS** — 29/29 |
| `npm run validate:m2:soak` | Yes | **PASS** — 31/31 (30m) |
| MCP Inspector | Yes | **PASS** — CLI tools/resources/schemas + tool calls |
| Cursor (production MCP client) | Yes | **PASS** — 2026-08-02T11:00Z live Agent MCP |
| Claude Desktop | Optional | Skipped — not in current development workflow |

## Implementation rules checklist

| Rule | Status |
|------|--------|
| No duplicate collectors / no polling loops | Pass — tools use Health cache / GetHealthSnapshot; stream only on MCP subscribe |
| Single persistent IPC session | Pass — `IpcSession` singleton |
| Subscribe/unsubscribe Health stream with MCP resource lifecycle | Pass — `StartHealthMonitoring` / `StopHealthMonitoring` on first/last subscriber |
| Cached tool responses | Pass — `HealthCache.ensureSnapshot` reuses fresh sample |
| Structured JSON only | Pass — envelope + `structuredContent` |
| Consistent error codes | Pass — `POLICY_DISABLED` and envelope codes aligned |
| `mcp.self` versions + namespaces + capabilities | Pass |
| Internal diagnostics (tool, latency, success/fail, IPC latency) | Pass — logger + MetricsRegistry |
| Automated tests | Pass — `npm test` |

## Automated tests

```text
cd apps/pulse_mcp && npm test
```

Result: **19/19** green.

## Harness

```text
cd apps/pulse_mcp && npm run validate:m2
cd apps/pulse_mcp && npm run validate:m2:soak
```

| Run | Result |
|-----|--------|
| `validate:m2` | **29/29** — tools, schemas, resources, subscribe/unsubscribe, reconnect |
| `validate:m2:soak` | **31/31** — 1802s, 180 samples, heap growth **−0.7 MB** |

## MCP Inspector

Headless CLI with `apps/pulse_mcp/scripts/mcp-inspector.m2.json` — **PASS** (`tools/list`, `resources/list`, schemas, `system.cpu`, `mcp.self`, resource read).

## Cursor (required) — PASS

Production client: Cursor Agent MCP server `project-0-Pulse-pulse` (`.cursor/mcp.json`).

| Check | Result | Evidence |
|-------|--------|----------|
| Connect | Pass | `serverStatus: ready`, `servicePipeConnected: true` |
| `mcp.self` | Pass | versions, namespaces `mcp`/`system`, capabilities |
| `system.health` | Pass | structured JSON, ISO-8601, null + unavailable |
| `system.cpu` | Pass | incl. `forceRefresh` live IPC |
| `system.memory` | Pass | |
| `system.gpu` | Pass | temp present; fanRpm null + unavailable |
| `system.storage` | Pass | volumes/disks; SSD temp unavailable |
| `system.network` | Pass | |
| Resource `pulse://system/cpu` | Pass | `FetchMcpResource` JSON |
| Resource `pulse://system/memory` | Pass | |
| Resource `pulse://system/gpu` | Pass | |
| Resource `pulse://system/network` | Pass | |
| Resource `pulse://system/health` | Pass | |
| Subscriptions | Pass | `activeSubscriptions` = all five URIs; resource `observedAt` advanced while subscribed |
| Diagnostics counters | Pass | after tools: `requestsServed: 7`, `requestsFailed: 0`, `lastRequestTool: system.network`, latencies exposed |
| Reconnect / session stability | Pass | Cursor session stayed connected (`uptimeSeconds` advancing, `ipcError: null`); stdio reconnect covered by harness |

## Claude Desktop (optional)

Skipped.

## Sign-off

| Role | Required | Result |
|------|----------|--------|
| Automated (vitest) | Yes | **PASS** |
| Harness `validate:m2` | Yes | **PASS** |
| Harness `validate:m2:soak` | Yes | **PASS** |
| MCP Inspector CLI | Yes | **PASS** |
| Cursor | Yes | **PASS** |
| Claude Desktop | No | Skipped |

**M2 freeze:** 2026-08-02 — required gates complete.  
**M3:** unblocked.
