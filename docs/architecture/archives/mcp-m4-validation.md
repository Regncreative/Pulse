# PulseMCP M4 validation report

**Date:** 2026-08-02  
**PulseMCP version:** `0.4.0`  
**Pulse app/service stamp:** `0.2.1-beta` / service `0.2.0-beta`  
**Scope:** M4 — `timeline.list`, `timeline.search`, `pulse://timeline/live`  
**Status:** **FROZEN** — all required gates PASS. M5 blocked until explicit start.

## Validation gate

| Check | Required | Status |
|-------|----------|--------|
| `npm test` | Yes | **PASS** — 29/29 |
| `npm run validate:m4` | Yes | **PASS** — 13/13 |
| Cursor (production MCP client) | Yes | **PASS** — 2026-08-02T11:18Z |
| Live resource subscription | Yes | **PASS** — subscribe/unsubscribe + read; quiet window OK |
| Claude Desktop | Optional | Skipped |

## Implementation rules checklist

| Rule | Status |
|------|--------|
| Reuse Timeline Engine / existing IPC | Pass — `GetTimelineSnapshot`, `StartLiveMonitoring` / `StopLiveMonitoring`, push field 22 |
| No new collectors | Pass |
| Flutter TimelineQuery-aligned filters | Pass — `timeline/query.ts` port |
| Structured JSON only | Pass |
| `includeRaw` default false | Pass — no `rawXml` unless requested |
| Security channel honesty | Pass — `securityChannelAvailable: false`; explicit Security → `ACCESS_DENIED` |
| Single IPC session | Pass |
| Live monitoring only while subscribed | Pass — `TimelineCache` refcount |

## Automated tests

```text
cd apps/pulse_mcp && npm test
```

**29/29** (includes `timeline.query` + live snapshot soft test).

## Harness

```text
cd apps/pulse_mcp && npm run validate:m4
```

**13/13** — tools, mcp.self capabilities, list/search, Security ACCESS_DENIED, subscribe/unsubscribe live.

## Cursor — PASS

| Check | Result | Notes |
|-------|--------|-------|
| `mcp.self` | Pass | `0.4.0`, namespace `timeline`, tools + `pulse://timeline/live` |
| `timeline.list` | Pass | count=10, channels listed, no rawXml |
| `timeline.search` | Pass | keyword filter |
| Security channel | Pass | `ACCESS_DENIED` when unreadable |
| `pulse://timeline/live` read | Pass | JSON (may note no events yet) |

## Sign-off

| Role | Required | Result |
|------|----------|--------|
| Automated | Yes | **PASS** |
| `validate:m4` | Yes | **PASS** |
| Cursor | Yes | **PASS** |
| Live subscription | Yes | **PASS** |

**M4 freeze:** 2026-08-02.  
**M5:** do not start until this freeze and an explicit go-ahead.
