# PulseMCP M7 validation report

**Date:** 2026-08-02  
**PulseMCP version:** `0.7.0`  
**Pulse app/service stamp:** `0.2.1-beta`  
**Scope:** M7 — MCP productization (Settings, Diagnostics, installer, client registration)  
**Status:** **FROZEN** — gates below. M8 blocked until explicit start.  
**Constraint:** No new MCP tools / protocol / collectors.

## Validation gate

| Check | Required | Status |
|-------|----------|--------|
| `cd apps/pulse_mcp && npm test` | Yes | **PASS** — 39/39 |
| Flutter `mcp_json_config_editor_test` | Yes | **PASS** — 1/1 |
| `flutter build windows` (Debug) | Yes | **PASS** |
| Settings → AI Integration | Yes | Implemented — enable, auto-start, status, register, logs, docs |
| Cursor global register / unregister | Yes | Provider + marker-gated unregister |
| Diagnostics → MCP | Yes | Status file metrics section |
| Installer packages PulseMCP | Yes | `package_pulsemcp.ps1` + Inno cleanup |
| Pipe max ≥ 8 | Yes | `kMaxPipeInstances = 8` |
| Docs (AI / install / troubleshoot / security / upgrade) | Yes | `docs/guides/*` |
| No M8 / no new tools | Yes | Confirmed |
| Clean install / upgrade / uninstall | Manual | Checklist below |
| Reconnect / settings persistence | Manual | Checklist below |

## Implementation checklist

| Item | Status |
|------|--------|
| Policy write `%LOCALAPPDATA%\Pulse\mcp\policy.json` | Pass |
| Status heartbeats `status.json` | Pass |
| `--status-daemon` for Start with Pulse | Pass |
| Provider abstraction (Cursor / Claude / ChatGPT stub) | Pass |
| Config backup + JSON validate | Pass |
| Uninstall `--cleanup-registrations` | Pass |
| Privacy disclosure in Settings | Pass |

## Manual checklist (sign at freeze)

- [ ] Clean install Setup.exe → Pulse + PulseService + `PulseMCP.exe` + `runtime\node.exe` present (no system Node.js required)
- [ ] Enable MCP → `mcp.self` works from Cursor after Register
- [ ] Unregister removes only `pulse` entry; other servers remain
- [ ] Upgrade preserves `policy.json`
- [ ] Uninstall runs registration cleanup for Pulse-owned markers
- [ ] Disable MCP → tools return `POLICY_DISABLED`
- [ ] Diagnostics MCP section updates while status-daemon or Cursor session runs
- [ ] Settings persistence across app restart

## Automated

```text
cd apps/pulse_mcp && npm test
cd apps/pulse_app && flutter test test/mcp_json_config_editor_test.dart
```

## Sign-off

| Role | Result |
|------|--------|
| Automated (MCP + Flutter editor test) | **PASS** |
| Productization surfaces | **PASS** (code complete) |
| Full installer clean-room | Operator checklist above |

**M7 freeze:** 2026-08-02.  
**M8:** do not start until this freeze and an explicit go-ahead.
