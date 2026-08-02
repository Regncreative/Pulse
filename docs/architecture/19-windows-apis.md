# 19 — Windows APIs

## Purpose

Verified Windows APIs for **Pulse v1** (Event Log collector). Future milestone APIs are listed as deferred.

Pulse never invents undocumented APIs.

---

## v1 — Required

### Event Log (Wevtapi)

| Function | Purpose | Reference |
|----------|---------|-----------|
| `EvtSubscribe` | Pull subscription (signal event) | [EvtSubscribe](https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtsubscribe) |
| `EvtNext` | Batch retrieve | [EvtNext](https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtnext) |
| `EvtQuery` | Historical / gap fill | [EvtQuery](https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtquery) |
| `EvtRender` | Values (hot); XML (lazy) | [EvtRender](https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtrender) |
| `EvtCreateBookmark` / `EvtUpdateBookmark` | Resume | [Bookmarking](https://learn.microsoft.com/en-us/windows/win32/wes/bookmarking-events) |
| `EvtClose` | Release handles | [EvtClose](https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtclose) |
| `EvtOpenChannelEnum` / `EvtNextChannelPath` | Optional channel list | Channel enum APIs |

Library: `Wevtapi.lib`

### Service Control / Pipes / Security

Same as before for SCM, `CreateNamedPipe`, IOCP, token SID checks — see prior inventory. Links:

- [CreateNamedPipe](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createnamedpipew)
- [StartServiceCtrlDispatcher](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-startservicectrldispatchera)

---

## Deferred — Not Linked in v1 Binary

| Area | APIs | Milestone |
|------|------|-----------|
| ETW | `StartTrace`, `OpenTrace`, `ProcessTrace`, TDH | M2 — [20](20-etw-integration.md) |
| WMI | MI_Session_Subscribe, etc. | M3 — [22](22-wmi-integration.md) |

---

## R3 — Inventory Engine (ADR-011)

Observation-only. Linked as domains ship. Primary APIs:

| Domain | Primary APIs |
|--------|----------------|
| Services | `OpenSCManagerW`, `EnumServicesStatusExW`, `OpenServiceW`, `QueryServiceConfigW`, `QueryServiceConfig2W` |
| Drivers | Same SCM APIs with `SERVICE_DRIVER` (SCM subset; not Driver Store) |
| Software | `RegOpenKeyExW` / `RegEnumKeyExW` on HKLM Uninstall (+ WOW6432Node); HKCU/Store omitted |
| USB | `SetupDiGetClassDevsW` enumerator `USB` + `SetupDiGetDeviceInstanceIdW`; fallback `CM_Get_Device_IDW` |
| PCI | Same SetupAPI pattern with enumerator `PCI` (membership); GPU PCIe link stays Health enrichment |

See [ADR-011](decisions/ADR-011-inventory-engine.md) for full domain catalog, fallbacks, and permissions.

---

## Explicitly Never Used

Hooks, injection, remote thread, registry writes, undocumented Nt* for collection, legacy `ReadEventLog` as primary path.

---

## Related Documents

- [21 — Event Viewer Integration](21-event-viewer-integration.md)
