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
| Displays | SetupAPI class `Monitor` via `SetupDiClassGuidsFromNameW` + `SetupDiGetClassDevsW`; description fallback `EnumDisplayDevicesW` |
| Audio | SetupAPI class `Media` (no fallback) |
| Bluetooth | SetupAPI class `Bluetooth`; empty → `unsupported` |
| Printers | `EnumPrintersW` (`PRINTER_ENUM_LOCAL \| PRINTER_ENUM_CONNECTIONS`), level 2, read-only |
| Battery | SetupAPI class `Battery` + `IOCTL_BATTERY_QUERY_*` via `GUID_DEVINTERFACE_BATTERY`; fallback `GetSystemPowerStatus` (`partial`, id `system_power`) |
| Motherboard | `GetSystemFirmwareTable('RSMB')` shared helper; SMBIOS Type 2 (Baseboard Information); singleton id `motherboard` |
| Bios | `GetSystemFirmwareTable('RSMB')` shared helper; SMBIOS Type 0 (BIOS Information); singleton id `bios` |
| Cpu | Registry `ProcessorNameString` + `GetLogicalProcessorInformationEx` (topology/cache) + `__cpuid` (vendor/instruction set); singleton id `cpu`; same identity patterns as `collectors/system_overview_info.cpp` `EnrichCpuOverview` (no merge with Health) |
| MemoryModules | `GetSystemFirmwareTable('RSMB')` shared helper; SMBIOS Type 17 (Memory Device) per slot; id = Device Locator string |
| Storage | `SetupDiGetClassDevsW`/`SetupDiEnumDeviceInterfaces` via `GUID_DEVINTERFACE_DISK` + `\\.\PhysicalDriveN` + `IOCTL_STORAGE_QUERY_PROPERTY` / `IOCTL_STORAGE_GET_DEVICE_NUMBER` / `IOCTL_DISK_GET_LENGTH_INFO` / `IOCTL_DISK_GET_DRIVE_GEOMETRY_EX` / `IOCTL_DISK_GET_DRIVE_LAYOUT_EX`; identity only, not live SMART telemetry |
| NetworkAdapters | `GetAdaptersAddresses` primary; Network Adapters class registry (`NetCfgInstanceId` match) for driver provider/version/date enrichment only; id = AdapterName GUID string |

See [ADR-011](decisions/ADR-011-inventory-engine.md) for full domain catalog, fallbacks, and permissions.

---

## Explicitly Never Used

Hooks, injection, remote thread, registry writes, undocumented Nt* for collection, legacy `ReadEventLog` as primary path.

---

## Related Documents

- [21 — Event Viewer Integration](21-event-viewer-integration.md)
