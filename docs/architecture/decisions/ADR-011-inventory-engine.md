# ADR-011: Inventory Engine (R3)

**Status:** **Accepted** (2026-08-02)

**Date:** 2026-08-02

**Depends on:** R1 complete, R2 frozen, [ADR-010](ADR-010-mcp-first-class-product.md) (MCP product model)

**Normative plan:** [39-inventory-engine-r3.md](../39-inventory-engine-r3.md)

---

## Context

Roadmap R3 requires a read-only **Inventory Engine** covering system description domains (services, drivers, software, USB, PCI, and phased hardware catalogs).

Today Pulse already collects overlapping **static / live** hardware facts under **System Health** (`HealthStaticInfo`, `HealthSample`, process inventory). Without a clear boundary, R3 risks duplicate collectors and Health cadence bleed into Inventory.

ADR-010 reserves the full Windows service catalog for Inventory; `service.status` remains PulseService identity until `inventory.services` ships.

### Codebase anchors (as of R2 freeze)

| Path | Relevance |
|------|-----------|
| `collectors/health_metrics_collector.*` | Health orchestrator — **not** Inventory |
| `collectors/system_overview_info.*` | CPU/SMBIOS/disk/net helpers — share later; no dual Health-tick walks for Inventory lists |
| `collectors/gpu_adapter_info.*` | SetupAPI PCIe enrichment — reuse for PCI display adapters |
| `diagnostics/service_identity.cpp` | SCM for **PulseService only** |
| Reports `hardwareInventory` | Subset of `HealthStaticInfo` — **must migrate** to Inventory SSOT |

No WMI collectors today. Doc 33 has no `inventory.*` tools yet.

---

## Decision

### D0 — Descriptive Inventory vs live Health

| Engine | Role |
|--------|------|
| **Health** | Live telemetry (rates, samples, process metrics) |
| **Inventory** | System **description** / configuration catalog |

Inventory is **not** another monitoring engine. No Health timers, no 1 Hz Inventory resources, no live telemetry fields on Inventory objects.

### D1 — Separate engine

```
PulseService
├── Health path → HealthMetricsCollector, process inventory, ETW net, …
└── Inventory path → InventoryEngine + one collector per domain
        └── shared read-only helpers only (SetupAPI, SMBIOS, SCM utilities)
```

- Not inside Health collectors or monitoring loops.
- Not on service/app startup — **lazy**, **requested domains only**.
- UI / Reports / MCP use Inventory IPC only for catalogs.

### D2 — Single source of truth per domain

- Exactly **one collector** per domain.
- Never collect the same membership from multiple APIs unless a **documented primary + fallback** is listed in the domain catalog.
- Domains own their data models; no cross-domain collector dependencies.
- Shared **utility libraries** only (not shared collectors).

### D3 — Uniform cache contract (all domains)

| Contract field | Behavior |
|----------------|----------|
| `cache_ttl_ms` | Soft TTL (domain-specific value) |
| `generation` | Monotonic `uint64`; increments on each successful collect that replaces cache |
| `generated_at_unix_ms` | Collect wall time |
| Refresh trigger | Cache miss, TTL expiry, or `force_refresh=true` |
| `force_refresh` | Bypass TTL; re-collect; bump `generation` on success |
| `since_generation` | Incremental diff when supported and base matches; else full resync |

Semantics identical across domains; only TTL and incremental eligibility differ.

### D4 — Additive IPC; structured data only

- Envelope fields **37+**; hand-maintained codecs.
- **No UI-specific fields. No pre-formatted strings.** Structured data for MCP/UI/Reports.

### D5 — Stable identifiers

Never use display names as identities.

| Domain | Stable id |
|--------|-----------|
| Services | Service name (SCM key) |
| Drivers | Driver service key |
| Software | ProductCode or uninstall registry key |
| USB / PCI / device classes | Device instance ID / path |
| Printers | Spooler printer name (documented key) |
| Motherboard / BIOS / CPU | Singleton ids `motherboard` / `bios` / `cpu` |
| Memory module | SMBIOS locator/bank |
| Storage | Disk device id |
| Network adapter | Interface GUID |

### D6 — Failure model (never silent)

| Status | Meaning |
|--------|---------|
| `available` | Success for this scope |
| `unsupported` | Platform cannot provide domain |
| `access_denied` | Insufficient privileges |
| `partial` | Incomplete rows/fields or cap hit (`truncated` flag + `status_detail`) |
| `error` | Unexpected failure |

### D7 — MCP from day one

Objects designed for `inventory.*` tools. Schemas in doc 33 as domains ship; tools unregistered or `available: false` until collectors exist.

### D8 — Reports SSOT

Inventory is the **single source** for Hardware / Software / Driver / Service / System inventory reports. Reports **must not** bypass Inventory collectors. Migrate `hardwareInventory` off `HealthStaticInfo` during R3.

### D9 — Performance

Never block startup. Everything lazy. Only requested domains collected. Prefer `partial` over hanging.

### D10 — Testability

Each collector independently testable: unit + mock Win32 seams + golden datasets + integration + wire tests.

### D11 — R3 complete only when

- Every planned domain (P0 + P1 + P2) implemented  
- Every domain has tests, documentation, MCP-ready schemas  
- Reports consume Inventory  
- No duplicate collectors  
- Release build passes  
- Performance validation passes  

---

## Domain catalog

### Services (P0)

| | |
|--|--|
| **Primary** | `OpenSCManagerW`, `EnumServicesStatusExW` (`SERVICE_WIN32`, `SERVICE_STATE_ALL`), `QueryServiceConfigW` / `QueryServiceConfig2W` |
| **Fallback** | None for membership; omit restricted fields → may yield `partial` |
| **Stable id** | Service name |
| **TTL** | 30 s |
| **Incremental** | Yes (by name) |
| **MCP / Reports** | `inventory.services` / Service Inventory |

### Drivers (P0 — SCM driver subset)

| | |
|--|--|
| **Primary** | `EnumServicesStatusExW` (`SERVICE_DRIVER`) |
| **Fallback** | SetupAPI driver properties to **enrich** version/provider only (not membership) |
| **Stable id** | Driver service key |
| **TTL** | 60 s |
| **Incremental** | Yes |
| **Honesty** | Not full Driver Store |
| **MCP / Reports** | `inventory.drivers` / Driver Inventory |

### Installed software (P0)

| | |
|--|--|
| **Primary** | HKLM (+ WOW6432Node) Uninstall registry (read-only) |
| **Fallback** | None; Store/UWP gap documented |
| **Stable id** | ProductCode or uninstall key |
| **TTL** | 300 s |
| **Incremental** | Full replace |
| **MCP / Reports** | `inventory.software` / Software Inventory |

### PCI (P0)

| | |
|--|--|
| **Primary** | SetupAPI present PCI devices |
| **Fallback** | Existing GPU PCIe helper for enrichment of matching adapters only |
| **Stable id** | Device instance ID |
| **TTL** | 60 s |
| **Incremental** | Yes |
| **MCP / Reports** | `inventory.pci` / Hardware Inventory |

### USB (P0)

| | |
|--|--|
| **Primary** | SetupAPI USB class/enumerator |
| **Fallback** | CfgMgr32 device ID if instance string empty |
| **Stable id** | Device instance ID |
| **TTL** | 60 s |
| **Incremental** | Yes |
| **MCP / Reports** | `inventory.usb` / Hardware Inventory |

### Displays (P1)

Primary: SetupAPI monitor/display. Fallback: `EnumDisplayDevicesW` for empty description. Id: instance ID. TTL 60 s. MCP `inventory.displays`.

### Audio (P1)

Primary: SetupAPI audio/media. No fallback. Id: instance ID. TTL 60 s. MCP `inventory.audio`.

### Bluetooth (P1)

Primary: SetupAPI Bluetooth. Empty → `unsupported`. Id: instance ID. TTL 60 s. MCP `inventory.bluetooth`.

### Printers (P1)

Primary: `EnumPrintersW` (read-only). No fallback. Id: spooler printer name. TTL 120 s. MCP `inventory.printers`.

### Battery (P1)

Primary: SetupAPI battery class + `IOCTL_BATTERY_QUERY_*`. Fallback: `GetSystemPowerStatus` aggregate only (`partial` / id `system_power`). TTL 30 s. MCP `inventory.battery`.

### Motherboard / BIOS / CPU / Memory / Storage / Network (P2)

| Domain | Primary | Fallback | Id | TTL |
|--------|---------|----------|----|-----|
| Motherboard | SMBIOS Type 2 via one RSMB read helper | None | `motherboard` | 300 s |
| BIOS | SMBIOS Type 0 (same helper) | None | `bios` | 300 s |
| CPU | Shared GLPIEx/CPUID helper (also feeds Health static) | None | `cpu` | 300 s |
| Memory modules | SMBIOS Type 17 list (same RSMB helper) | None | Locator | 300 s |
| Storage | Storage/SetupAPI disk identity list | None | Disk device id | 120 s |
| Network adapters | `GetAdaptersAddresses` | SetupAPI net class enrichment only | Interface GUID | 60 s |

One SMBIOS firmware table read may project motherboard + BIOS + memory domains (single utility parse; not three independent firmware fetches).

---

## Alternatives considered

| Alternative | Why rejected |
|-------------|--------------|
| Inventory as monitoring | Violates descriptive vs telemetry split |
| Multi-API membership without primary | Duplicate truth |
| Formatted strings on wire | Breaks MCP / Reports |
| Reports via HealthStaticInfo forever | Bypasses Inventory SSOT |
| Collect all domains at startup | Blocks startup |

---

## Consequences

- R3 **complete** bar = P0 + P1 + P2 with tests, docs, MCP schemas, report SSOT, release + perf validation.
- Implementation may proceed; each domain ships only with D2–D11 compliance.
- Update doc 19 / 33 as domains land; migrate hardware report to Inventory.

---

## References

- [34 — Engineering roadmap](../34-engineering-roadmap.md) R3
- [39 — Inventory Engine plan](../39-inventory-engine-r3.md)
- [19 — Windows APIs](../19-windows-apis.md)
- [33 — MCP bridge](../33-mcp-bridge.md)
- [ADR-003](ADR-003-named-pipe-ipc.md), [ADR-008](ADR-008-hot-cold-live-queues.md), [ADR-010](ADR-010-mcp-first-class-product.md)
- [AGENTS.md](../../../AGENTS.md)
- Microsoft Learn: EnumServicesStatusExW, SetupDiGetClassDevsW, GetSystemFirmwareTable, Battery enumeration
