# ADR-011: Inventory Engine (R3)

**Status:** Proposed — awaiting maintainer acceptance (no Inventory collector code until Accepted)

**Date:** 2026-08-02

**Depends on:** R1 complete, R2 frozen, [ADR-010](ADR-010-mcp-first-class-product.md) (MCP product model)

**Normative plan:** [39-inventory-engine-r3.md](../39-inventory-engine-r3.md)

---

## Context

Roadmap R3 requires a read-only **Inventory Engine**: Services, Drivers, Installed software, USB, PCI (required), with optional displays/battery and a broader hardware catalog for product completeness.

Today Pulse already collects overlapping **static / live** hardware facts under **System Health**:

| Area | Where today | Nature |
|------|-------------|--------|
| CPU model / topology / caches | `HealthStaticInfo` | Static summary |
| GPU identity + PCIe link | `HealthStaticInfo` + GPU helpers | Static / semi-static |
| Memory module **summary** (SMBIOS Type 17 aggregates) | `HealthStaticInfo` | Static summary |
| Primary disk identity | `HealthStaticInfo` | Static summary |
| Volumes / physical disks (live sizes) | `HealthSample` | Live metrics |
| Active network adapter | `HealthStaticInfo` + live net | Live + identity |
| Process inventory | `HealthProcessInventoryUpdate` | High-frequency |

Without a clear boundary, R3 risks **duplicate collectors**, Health cadence bleed into Inventory, and MCP/UI confusion.

ADR-010 already reserves full Windows service catalog for Inventory and keeps `service.status` as PulseService identity until then.

### Codebase anchors (as of R2 freeze)

| Path | Relevance |
|------|-----------|
| `collectors/health_metrics_collector.*` | Health orchestrator (static + 1 Hz sample + process inventory) — **not** Inventory |
| `collectors/system_overview_info.*` | CPU topology/CPUID, SMBIOS RAM summary, Storage IOCTL disk identity, IP Helper net — **share helpers later**, do not dual-walk on Health tick for Inventory lists |
| `collectors/gpu_adapter_info.*` | Only SetupAPI usage today (PCIe link); reuse for PCI/display-adapter rows |
| `collectors/hardware_sensors_collector.*` | SMART/temp into Health sample — stay Health |
| `diagnostics/service_identity.cpp` | SCM for **PulseService only**; no `EnumServicesStatusEx` machine catalog yet |
| Reports `hardwareInventory` | Subset of `HealthStaticInfo` only (`report_exporter.dart`) — R4 inventory templates consume Inventory IPC once P0/P2 ship |

No WMI collectors in service today. Doc 33 has **no** `inventory.*` tools registered yet.

---

## Decision

### D1 — Inventory is a separate engine

```
PulseService
├── Health path (unchanged cadence)     → HealthMetricsCollector, process inventory, ETW net, …
└── Inventory path (on-demand)          → InventoryEngine + inventory/* collectors
        └── may call shared read-only helpers (SetupAPI, SMBIOS, SCM enum)
```

- Inventory **must not** live inside `HealthMetricsCollector` or Health monitoring loops.
- Inventory **must not** start on service boot; first work happens on explicit IPC request.
- Flutter Inventory UI and Reports/MCP consume Inventory IPC only — never call Health collectors directly for catalog rows.
- Health UI continues to use Health IPC for live metrics; it may **display** inventory-backed detail later by calling Inventory RPCs (optional), but R3 does not merge engines.

### D2 — Shared helpers, not shared collectors

Low-level read-only helpers (e.g. SetupAPI enum wrapper, SMBIOS `GetSystemFirmwareTable('RSMB')` parser, SCM open) may live under `service/pulse_service/src/windows/` or `collectors/common/` and be used by **both** Health and Inventory over time.

**Forbidden:** two independent full implementations of the same catalog enumeration that diverge (e.g. two SetupAPI USB walkers). Prefer one helper, two call sites with different projection/filter.

**GPU PCI link properties** already in `gpu_adapter_info.cpp` → extract or reuse for PCI inventory rows that match display adapters; do not fork a second PCIe reader.

### D3 — Snapshot-first; no high-frequency Inventory polling

| Mode | R3 |
|------|-----|
| Default | Per-domain `Get*Inventory` / `GetInventorySnapshot` request → response |
| Cache | In-memory per-domain snapshot + `generated_at` + monotonic `generation` |
| Client refresh | Explicit `force_refresh=true` or TTL expiry (default TTL **60 s** for device catalogs; **30 s** for services state; **300 s** for software) |
| Live push | **Not required for R3 exit.** No `StartInventoryMonitoring` in v1 success metrics |
| Health 1 Hz | Inventory never joins Health sample timer |

Idle CPU remains near zero when Inventory UI is closed.

### D4 — Cache + refresh + incremental when useful

Each domain response includes:

- `available` / `status` (see D8)
- `generated_at_unix_ms`, `generation` (uint64)
- `truncated` + `limit` when capped
- Optional `delta` when client sends `since_generation` and the domain supports incremental

**Incremental policy (per domain):**

| Domain | Incremental? | Mechanism |
|--------|--------------|-----------|
| Services | Yes (preferred) | Diff by service name: upserts + removed_names |
| Drivers / USB / PCI / Displays / Audio / Bluetooth / Printers | Yes when cheap | Diff by device instance id |
| Software | Full replace default | Registry enum cost; optional later hash of key set |
| Battery | Full replace | Small N |
| Motherboard / BIOS / CPU static | Full replace | Tiny |
| Memory modules / Storage / Network adapters (lists) | Full replace or id-diff | Prefer id-diff when N grows |

If `since_generation` is unknown/stale → **full snapshot** (`full_resync=true`). Never invent removed rows.

### D5 — Additive IPC only

- Extend `pulse.proto` Envelope `oneof` from field **37+** (35/36 = Timeline detail).
- Hand-maintain C++/Dart wire codecs (repo practice).
- Old clients ignore unknown fields; missing Inventory RPCs → structured error, not crash.
- Prefer **per-domain RPCs** for bounded payloads; optional aggregate `GetInventorySnapshot` that fans out to cached domains without re-collecting fresh unless `force_refresh`.

Illustrative (final field numbers in proto comments when implemented):

```text
GetServicesInventory / ServicesInventory
GetDriversInventory / DriversInventory
GetSoftwareInventory / SoftwareInventory
GetUsbInventory / UsbInventory
GetPciInventory / PciInventory
GetInventoryDomain   { domain_id, force_refresh, since_generation, limit, offset }
GetInventorySnapshot { domains[], force_refresh }  // optional aggregate
```

### D6 — MCP planned from day one (schemas before tools)

Align with ADR-010:

| Phase | Action |
|-------|--------|
| ADR accepted | Document `inventory.*` tool + resource names + JSON schemas in doc 33 (additive) |
| Collector ships | Wire IPC → PulseMCP tool returns live JSON |
| Before collector | Tool **unregistered** or returns `available: false` with reason — never fake rows |

Planned tools (observation): `inventory.services`, `inventory.drivers`, `inventory.software`, `inventory.usb`, `inventory.pci`, plus phased domains. Pagination/`limit`/`offset` required (ADR-010).

`service.status` remains PulseService identity until `inventory.services` ships; then catalog stub flips to available and may deep-link.

Resources: Inventory is **not** 1 Hz; optional resource that republishes only when `generation` changes after manual/TTL refresh.

### D7 — UI independent of collectors

```
InventoryPage → InventorySessionController → PulseIpcClient → Envelope
```

- No FFI to Win32 from Flutter for catalogs.
- Client-side search/filter only over received rows.
- Virtualized lists; lazy details if a future `GetInventoryItemDetail` is added.

### D8 — Graceful “not supported” / unavailable

Every domain response uses an explicit status (wire enum or string code):

| Status | Meaning |
|--------|---------|
| `available` | Rows are best-effort complete for this scope |
| `unsupported` | Platform/SKU cannot provide this domain (e.g. no battery class) |
| `access_denied` | API failed for privileges; rows may be empty |
| `truncated` | Cap hit; `truncated=true` |
| `error` | Unexpected failure; `error_code` + explainable message |

UI/MCP show human explanation; **never** invent placeholder devices. Empty + `available` is valid (zero printers).

### D9 — No startup delay

`PulseService` start path does **not** enumerate Inventory domains. Collectors run only on IPC request (or cache fill). Timeouts per domain (suggest **5–15 s** hard cap) with partial results preferred over hanging the pipe.

### D10 — Phased domain scope

#### P0 — Required for R3 roadmap exit (doc 34)

Services, Drivers (ADR subset), Installed software, USB, PCI.

#### P1 — Optional same milestone if time-boxed

Displays, Battery, Audio devices, Bluetooth, Printers.

#### P2 — Static hardware catalogs (Inventory-owned lists; avoid Health duplication)

Motherboard, BIOS, CPU information (static identity/topology list fields), Memory **modules** (per-DIMM list), Storage **devices** (all disks), Network **adapters** (all interfaces).

Implementation rule for P2:

- Prefer **expanding shared SMBIOS / SetupAPI / Storage / IP Helper readers** used to populate Inventory lists.
- Health keeps **dashboard summaries** (`HealthStaticInfo` / live sample). Do not run Inventory collectors on the Health timer.
- Over time, HealthStaticInfo may call the same helpers for summaries (refactor), but R3 must not create a second SMBIOS walk on every Health tick.

#### Explicitly out of Inventory Engine

- **Process inventory** — remains Health-only (ADR-009 / existing process path).
- Live CPU%/GPU%/net bps — Health only.
- Service start/stop, driver install, software uninstall — never.

---

## Domain catalog (normative for design)

For each domain: intended APIs (Microsoft-documented), permissions, cost, refresh, cache, failure, MCP, reports.

### Services (P0)

| Aspect | Decision |
|--------|----------|
| **APIs** | `OpenSCManagerW` (CONNECT), `EnumServicesStatusExW` (`SERVICE_WIN32`, `SERVICE_STATE_ALL`), `OpenServiceW`, `QueryServiceConfigW`, `QueryServiceConfig2W` (DESCRIPTION) — [EnumServicesStatusExW](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-enumservicesstatusexw) |
| **Permissions** | Standard user: enumerate + config for most services; some binary paths / accounts may be empty without elevation — omit, do not invent |
| **Performance** | Medium (hundreds of services); avoid per-service `QueryServiceConfig` storms — batch carefully; cap detail |
| **Refresh** | On demand; TTL 30 s; incremental by service name |
| **Cache** | Full list + generation |
| **Failure** | SCM open fail → `access_denied` / `error` |
| **MCP** | `inventory.services` |
| **Reports** | R4 services template |

### Drivers (P0 — subset)

| Aspect | Decision |
|--------|----------|
| **APIs** | Primary: `EnumServicesStatusExW` with `SERVICE_DRIVER` **or** SetupAPI present devices with driver metadata via `SetupDiGetDevicePropertyW` / registry properties. Prefer **one** documented subset in user docs: e.g. “kernel + filesystem drivers from SCM” **or** “present devices with driver provider/version”. Do not claim full Driver Store parity. |
| **Permissions** | Standard user typically OK for SCM driver enum; some image paths restricted |
| **Performance** | Medium–high; no file version scrape for every row on first paint — lazy detail optional |
| **Refresh** | On demand; TTL 60 s; incremental by name/instance id |
| **Cache** | Yes |
| **Failure** | Partial list + status |
| **MCP** | `inventory.drivers` |
| **Reports** | R4 drivers template |

### Installed software (P0)

| Aspect | Decision |
|--------|----------|
| **APIs** | Read-only registry: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`, `HKLM\SOFTWARE\WOW6432Node\…\Uninstall`, `HKCU\…\Uninstall` via `RegOpenKeyExW` / `RegEnumKeyExW` / `RegQueryValueExW` |
| **Permissions** | HKLM readable for most; HKCU = current user context of service may **not** mirror interactive user — document: service session vs user hive limits; prefer listing machine-wide + document user-hive gap OR use documented impersonation only if ADR addendum accepts (default R3: **machine-wide + explicit limitation**) |
| **Performance** | High on busy machines; hard cap (e.g. 2000) + `truncated`; no icon extraction in service |
| **Refresh** | On demand; TTL 300 s; full replace |
| **Cache** | Yes |
| **Failure** | Missing keys → empty section; Store/UWP incomplete → documented limitation, not fake apps |
| **MCP** | `inventory.software` |
| **Reports** | R4 software template |

### PCI devices (P0)

| Aspect | Decision |
|--------|----------|
| **APIs** | SetupAPI: `SetupDiGetClassDevsW` (PCI enumerator / present devices), `SetupDiEnumDeviceInfo`, `SetupDiGetDeviceRegistryPropertyW`, `SetupDiGetDevicePropertyW` (incl. PCI location / IDs where available). Reuse GPU PCIe helpers for matching display adapters. |
| **Permissions** | Standard user for present devices |
| **Performance** | Medium; present-only filter |
| **Refresh** | On demand; TTL 60 s; incremental by instance id |
| **Cache** | Yes |
| **Failure** | `unsupported` rare; else `error` / partial |
| **MCP** | `inventory.pci` |
| **Reports** | Hardware inventory section |

### USB devices (P0)

| Aspect | Decision |
|--------|----------|
| **APIs** | SetupAPI with USB class/enumerator + CfgMgr32 device IDs as needed (`CM_Get_Device_IDW` family) — Microsoft SetupAPI/CfgMgr docs |
| **Permissions** | Standard user |
| **Performance** | Medium; hot-plug → rely on refresh, not continuous watch in R3 |
| **Refresh** | On demand; TTL 30–60 s; incremental by instance id |
| **Cache** | Yes |
| **Failure** | Empty + `available` if none |
| **MCP** | `inventory.usb` |
| **Reports** | Hardware section |

### Displays (P1)

| Aspect | Decision |
|--------|----------|
| **APIs** | SetupAPI `GUID_DEVCLASS_MONITOR` / display adapters; optional `EnumDisplayDevicesW` for GDI topology — document chosen primary |
| **Permissions** | Standard user |
| **Performance** | Low–medium |
| **Refresh** | On demand; TTL 60 s |
| **Cache** | Yes |
| **Failure** | `unsupported` if APIs fail |
| **MCP** | `inventory.displays` |
| **Reports** | Optional hardware |

### Audio devices (P1)

| Aspect | Decision |
|--------|----------|
| **APIs** | SetupAPI audio endpoint / media classes (present devices) |
| **Permissions** | Standard user |
| **Performance** | Low |
| **Refresh** | On demand; TTL 60 s |
| **Cache** | Yes |
| **Failure** | Graceful empty / unsupported |
| **MCP** | `inventory.audio` |
| **Reports** | Optional |

### Bluetooth (P1)

| Aspect | Decision |
|--------|----------|
| **APIs** | SetupAPI Bluetooth class / radio devices (present); no pairing actions |
| **Permissions** | Standard user; some radios restricted |
| **Performance** | Low–medium |
| **Refresh** | On demand; TTL 60 s |
| **Cache** | Yes |
| **Failure** | `unsupported` if no BT stack |
| **MCP** | `inventory.bluetooth` |
| **Reports** | Optional |

### Printers (P1)

| Aspect | Decision |
|--------|----------|
| **APIs** | Prefer `EnumPrintersW` (winspool) read-only **or** SetupAPI printers class — pick one in implementation notes |
| **Permissions** | Standard user |
| **Performance** | Low |
| **Refresh** | On demand; TTL 120 s |
| **Cache** | Yes |
| **Failure** | Empty list OK |
| **MCP** | `inventory.printers` |
| **Reports** | Optional |

### Battery (P1)

| Aspect | Decision |
|--------|----------|
| **APIs** | SetupAPI `GUID_DEVCLASS_BATTERY` + `DeviceIoControl` `IOCTL_BATTERY_QUERY_*` ([Enumerating Battery Devices](https://learn.microsoft.com/en-us/windows/win32/power/enumerating-battery-devices)); overview via `GetSystemPowerStatus` for aggregate |
| **Permissions** | Standard user |
| **Performance** | Low |
| **Refresh** | On demand; TTL 30 s (charge changes) — still **not** Health 1 Hz |
| **Cache** | Short TTL |
| **Failure** | Desktop without battery → `unsupported` or empty + reason |
| **MCP** | `inventory.battery` |
| **Reports** | Optional |

### Motherboard (P2)

| Aspect | Decision |
|--------|----------|
| **APIs** | SMBIOS via `GetSystemFirmwareTable` provider `RSMB` (Type 2 Baseboard) |
| **Permissions** | Standard user typically |
| **Performance** | Low (one firmware table parse) |
| **Refresh** | Rare; TTL 300 s+ |
| **Cache** | Long-lived |
| **Failure** | Parse fail → `unsupported` |
| **MCP** | `inventory.motherboard` |
| **Reports** | Hardware cover / identity |
| **Health overlap** | Do not re-parse SMBIOS on Health tick; share parser helper |

### BIOS (P2)

| Aspect | Decision |
|--------|----------|
| **APIs** | SMBIOS Type 0 (BIOS) via same `RSMB` table |
| **Permissions** | Standard user |
| **Performance** | Low |
| **Refresh** | Rare; TTL 300 s+ |
| **Cache** | Long-lived |
| **Failure** | `unsupported` |
| **MCP** | `inventory.bios` |
| **Reports** | Hardware identity |
| **Health overlap** | Shared SMBIOS helper |

### CPU information (P2)

| Aspect | Decision |
|--------|----------|
| **APIs** | Existing Health paths: `GetLogicalProcessorInformationEx`, CPUID — **project** into Inventory static CPU record; Inventory does not add a second live CPU sampler |
| **Permissions** | Standard user |
| **Performance** | Low for static; **zero** Inventory live sampling |
| **Refresh** | Rare (topology static for session) |
| **Cache** | Long-lived |
| **Failure** | Partial fields with has_* |
| **MCP** | `inventory.cpu` |
| **Reports** | Cover identity (also Health today) |
| **Health overlap** | Single helper feeding HealthStaticInfo + Inventory |

### Memory modules (P2)

| Aspect | Decision |
|--------|----------|
| **APIs** | SMBIOS Type 17 — **per-module list** (Health today exposes aggregates on `HealthStaticInfo`) |
| **Permissions** | Standard user |
| **Performance** | Low |
| **Refresh** | Rare; TTL 300 s |
| **Cache** | Long-lived |
| **Failure** | Empty modules + unsupported |
| **MCP** | `inventory.memory_modules` |
| **Reports** | Hardware |
| **Health overlap** | Shared SMBIOS; Health keeps summary fields |

### Storage devices (P2)

| Aspect | Decision |
|--------|----------|
| **APIs** | Storage IOCTL / SetupAPI disk class for **all** disks; volumes remain primarily Health live metrics — Inventory lists disk identity (model, serial, bus) without 1 Hz size polling |
| **Permissions** | Some serials need elevation — omit when denied |
| **Performance** | Medium |
| **Refresh** | On demand; TTL 120 s |
| **Cache** | Yes |
| **Failure** | Partial |
| **MCP** | `inventory.storage` |
| **Reports** | Hardware |
| **Health overlap** | Health keeps volume free-space samples; Inventory does not duplicate free-space polling |

### Network adapters (P2)

| Aspect | Decision |
|--------|----------|
| **APIs** | IP Helper (`GetAdaptersAddresses`) + SetupAPI for driver metadata — **all adapters** list |
| **Permissions** | Standard user |
| **Performance** | Low–medium |
| **Refresh** | On demand; TTL 60 s |
| **Cache** | Yes |
| **Failure** | Partial |
| **MCP** | `inventory.network_adapters` |
| **Reports** | Hardware |
| **Health overlap** | Health keeps active adapter + live throughput; Inventory lists adapters without net bps |

---

## PII & privacy

| Sensitive | Policy |
|-----------|--------|
| Service account names, binary paths | Include when available; never log to unstructured text logs |
| Software install paths, publishers | Allowed in IPC; redacted from service logs |
| Disk / DIMM serials | Allowed in Inventory; treat as sensitive in logs |
| MAC addresses | Allowed; document for MCP disclosure (ADR-010 privacy) |

No Inventory telemetry. MCP disclosure in Settings when inventory tools enabled (with MCP).

---

## Alternatives considered

| Alternative | Why rejected |
|-------------|--------------|
| Fold Inventory into Health monitoring | Couples catalogs to 1 Hz path; startup and idle cost |
| Duplicate SMBIOS/SetupAPI per feature | Drift and double work |
| WMI as primary Inventory source | Heavier; deferred unless ADR addendum; prefer Win32 |
| Continuous device notification threads in R3 | Complexity; refresh-on-demand sufficient for exit |
| Flutter Win32 inventory | Breaks architecture; privilege and maintenance cost |

---

## Consequences

### Positive

- Clear engine boundary; roadmap P0 exit without boiling the ocean
- MCP/report schemas ready before tools light up
- Honest unsupported/denied states
- No service-start Inventory tax

### Costs / follow-ups

- P1/P2 domains may ship after P0 inside the same ADR if time-boxed, else backlog tickets referencing this ADR
- Doc 19 must list only APIs actually linked
- Doc 33 additive `inventory.*` section when ADR accepted
- Pipe max instances 4→8 remains ADR-010 follow-up (MCP + UI + Inventory client)

### Implementation gate

**No Inventory collector or Envelope Inventory messages land until this ADR is Accepted** and [39](../39-inventory-engine-r3.md) status is Approved.

---

## References

- [34 — Engineering roadmap](../34-engineering-roadmap.md) R3
- [39 — Inventory Engine plan](../39-inventory-engine-r3.md)
- [19 — Windows APIs](../19-windows-apis.md)
- [33 — MCP bridge](../33-mcp-bridge.md)
- [ADR-003](ADR-003-named-pipe-ipc.md), [ADR-008](ADR-008-hot-cold-live-queues.md), [ADR-010](ADR-010-mcp-first-class-product.md)
- [AGENTS.md](../../../AGENTS.md)
- Microsoft Learn: EnumServicesStatusExW, SetupDiGetClassDevsW, GetSystemFirmwareTable, Battery enumeration
