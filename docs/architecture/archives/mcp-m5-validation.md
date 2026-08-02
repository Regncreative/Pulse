# PulseMCP M5 validation report

**Date:** 2026-08-02  
**PulseMCP version:** `0.5.0`  
**Pulse app/service stamp:** `0.2.1-beta` / service `0.2.0-beta`  
**Scope:** M5 — `diagnostics.snapshot`, `service.status`, `pulse://diagnostics/snapshot`, `pulse://mcp/status`  
**Status:** **FROZEN** — all required gates PASS. M6 blocked until explicit start.

## Validation gate

| Check | Required | Status |
|-------|----------|--------|
| `npm test` | Yes | **PASS** — 33/33 |
| `npm run validate:m5` | Yes | **PASS** — 16/16 |
| Cursor (production MCP client) | Yes | **PASS** — 2026-08-02T11:24Z |
| Diagnostics resource subscription | Yes | **PASS** — subscribe + updates on change |
| Reconnect | Yes | **PASS** — second session `diagnostics.snapshot` ok |
| `mcp.self` capability audit | Yes | **PASS** — `0.5.0`, namespaces + tools + resources |
| Claude Desktop | Optional | Skipped |

## Implementation rules checklist

| Rule | Status |
|------|--------|
| Reuse Diagnostics Engine / existing IPC | Pass — `GetDiagnosticsSnapshot` envelope field 30/31 |
| No duplicate collectors | Pass — TTL cache + poll only while resource subscribed |
| `service.status` = PulseService only | Pass — `catalog.available: false` |
| Structured JSON only | Pass |
| ISO-8601 UTC timestamps | Pass |
| Structured MCP errors | Pass |
| Resources publish on meaningful changes | Pass — snap fingerprint / mcp status compare key |
| Single IPC session | Pass |
| Read-only | Pass |

## Automated tests

```text
cd apps/pulse_mcp && npm test
```

**33/33** (includes diagnostics mappers + live soft test).

## Harness

```text
cd apps/pulse_mcp && npm run validate:m5
```

**16/16** — tools, resources, mcp.self capabilities, snapshot/status, reads, subscriptions, reconnect.

## Cursor — PASS

| Check | Result | Notes |
|-------|--------|-------|
| `mcp.self` | Pass | `0.5.0`, namespaces `diagnostics`/`service`, tools + resources |
| `diagnostics.snapshot` | Pass | service/pipeline/ipc/live populated |
| `service.status` | Pass | PulseService Running; catalog unavailable |
| `pulse://diagnostics/snapshot` | Pass | JSON read |
| `pulse://mcp/status` | Pass | versions `0.5.0`, full capability list |

## Sign-off

| Role | Required | Result |
|------|----------|--------|
| Automated | Yes | **PASS** |
| `validate:m5` | Yes | **PASS** |
| Cursor | Yes | **PASS** |
| Diagnostics subscription | Yes | **PASS** |
| Reconnect | Yes | **PASS** |
| mcp.self audit | Yes | **PASS** |

**M5 freeze:** 2026-08-02.  
**M6:** do not start until this freeze and an explicit go-ahead.
