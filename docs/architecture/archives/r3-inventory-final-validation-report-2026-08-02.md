# R3 — Inventory Engine final validation report (P0 + P1 + P2)

**Status:** PASS for the full R3 platform slice (P0 + P1 + P2) — release build /
Device Manager spot-check still open (see Known limitations)
**Date:** 2026-08-02
**ADR:** [ADR-011](../decisions/ADR-011-inventory-engine.md) (Accepted)
**Plan:** [39-inventory-engine-r3.md](../39-inventory-engine-r3.md)
**Roadmap:** [34-engineering-roadmap.md](../34-engineering-roadmap.md)
**Prior report:** [r3-inventory-p1-validation-report-2026-08-02.md](r3-inventory-p1-validation-report-2026-08-02.md)
(P0 + P1 only; P2 not started)

Constitution: observation only; Inventory describes; Health measures; no
invented rows.

---

## Verdict

**P0 + P1 + P2 Inventory platform validated.** All 16 ADR-011 domains are
collected, cached, exposed over IPC, rendered in the Flutter Inventory
browser with rich sectioned detail panels, consumed by Reports (Service /
Driver / Software / Hardware / **System**), and reserved (disabled) in
PulseMCP. This session covered the **Flutter UI, Reports, MCP schema, and
documentation** work described in doc 34's remaining R3 checkboxes; the P2
C++ collectors (`motherboard_collector`, `bios_collector`, `cpu_collector`,
`memory_modules_collector`, `storage_collector`,
`network_adapters_collector`, `smbios_table`) were already committed in a
prior session (`d5f197a` and earlier) and were **not modified or rewritten**
here, per instruction.

R3 is not yet marked **complete** in doc 34 — the release-build and Device
Manager/`msinfo32` spot-check checkboxes remain open (see Known limitations
§8–9). Do not open R4 until those close.

---

## Implemented domains

| Priority | Domain | Collector | Stable id | TTL | Primary API (doc 19 / ADR-011) |
|----------|--------|-----------|-----------|-----|----------------------------------|
| P0 | Services | SCM | service name | 30 s | `EnumServicesStatusExW` |
| P0 | Drivers | SCM drivers | driver service key | 60 s | SCM `SERVICE_DRIVER` subset |
| P0 | Software | Uninstall registry | ProductCode / uninstall key | 300 s | `RegEnumKeyExW` on HKLM Uninstall |
| P0 | USB | SetupAPI enum `USB` | instance ID | 60 s | `SetupDiGetClassDevsW` |
| P0 | PCI | SetupAPI enum `PCI` | instance ID | 60 s | `SetupDiGetClassDevsW` |
| P1 | Displays | SetupAPI class `Monitor` + `EnumDisplayDevicesW` | instance ID | 60 s | SetupAPI + fallback |
| P1 | Audio | SetupAPI class `Media` | instance ID | 60 s | `SetupDiGetClassDevsW` |
| P1 | Bluetooth | SetupAPI class `Bluetooth` | instance ID | 60 s | `SetupDiGetClassDevsW` |
| P1 | Printers | `EnumPrintersW` | spooler name | 120 s | `EnumPrintersW` level 2 |
| P1 | Battery | SetupAPI `Battery` + IOCTL; fallback `GetSystemPowerStatus` | instance ID / `system_power` | 30 s | `IOCTL_BATTERY_QUERY_*` |
| **P2** | **Motherboard** | `smbios_table` (RSMB) | `motherboard` | 300 s | `GetSystemFirmwareTable('RSMB')` Type 2 |
| **P2** | **BIOS** | `smbios_table` (RSMB) | `bios` | 300 s | `GetSystemFirmwareTable('RSMB')` Type 0 |
| **P2** | **CPU** | `cpu_collector` | `cpu` | 300 s | Registry + `GetLogicalProcessorInformationEx` + `__cpuid` |
| **P2** | **Memory modules** | `smbios_table` (RSMB) | SMBIOS Device Locator | 300 s | `GetSystemFirmwareTable('RSMB')` Type 17 |
| **P2** | **Storage** | `storage_collector` | SetupAPI disk instance ID | 120 s | `IOCTL_STORAGE_QUERY_PROPERTY` + friends |
| **P2** | **Network adapters** | `network_adapters_collector` | Adapter GUID string | 60 s | `GetAdaptersAddresses` + net class registry enrichment |

All 16 domains are marked `implemented: true` in
`apps/pulse_app/lib/presentation/inventory/inventory_catalog.dart`; the
System group in the Inventory tree no longer shows a "P2" reserved badge.

---

## API sources

Full citations: [19-windows-apis.md § R3](../19-windows-apis.md#r3--inventory-engine-adr-011)
and [ADR-011 § Domain catalog](../decisions/ADR-011-inventory-engine.md).
No undocumented or invented Windows APIs were introduced by this session
(no C++ was touched).

---

## What this session changed

| Area | Change |
|------|--------|
| `inventory_catalog.dart` | 6 System domains flipped `implemented: false → true` |
| `inventory_detail_model.dart` (new) | `InventoryDetailSection` model + per-domain section builders (Identity / Chassis / Topology / Capabilities / Hardware / Network / Driver) for motherboard, BIOS, CPU, memory modules, storage, network adapters |
| `inventory_page.dart` | `_allRows()` cases for the 6 P2 domains; flat `_InventoryDetail` replaced with a sectioned panel (section headers + selectable values + per-value copy) shared by every domain via `displaySections`; domain header item counts extended |
| `report_models.dart` | `ReportTemplate.systemInventory` (title/description/fileStem/CSV support/`systemInventoryDomains` SSOT list) |
| `reports_page.dart` | `_fetchSystemInventoryIfNeeded` fetches all 6 P2 domains in parallel when the System Inventory template is selected |
| `report_exporter.dart` | `systemInventoryCsv` / `systemInventoryJson` / HTML + PDF sections for the 6 domains, reusing the same `InventoryDetailSection` builders as the Flutter detail panel (single source of truth for field lists); `inventoryDomainCsv`/`inventoryDomainJson`/`_inventoryItemCount` extended with P2 cases; system-identity cover block for the System Inventory report now sources CPU/motherboard/BIOS from Inventory, never `HealthStaticInfo` |
| `apps/pulse_mcp/src/catalog/v1.ts` | `INVENTORY_TOOLS_REGISTERED` gains `inventory.motherboard` / `inventory.bios` / `inventory.cpu` / `inventory.memory` / `inventory.storage` / `inventory.network` (handlers still disabled) |
| `apps/pulse_mcp/schemas/inventory/` | `domain-snapshot.json` domain enum + `README.md` table extended for the 6 P2 tools |
| Docs | 33-mcp-bridge §16.1, 34-engineering-roadmap P2 checkboxes, 39-inventory-engine-r3 UI/Reports/MCP notes updated |

---

## Report validation

| Template | Source of truth | Status |
|----------|-----------------|--------|
| Services | Inventory `services` | Done (P0/P1 report) |
| Drivers | Inventory `drivers` | Done (P0/P1 report) |
| Software | Inventory `software` | Done (P0/P1 report) |
| Hardware | Inventory USB + PCI | Done (P0/P1 report) |
| **System** | Inventory motherboard + BIOS + CPU + memory modules + storage + network adapters | **Done this session** |

`healthStaticHardwareRows` remains in `report_exporter.dart` for backward
compatibility only; it is not called by any current report template
(re-confirmed by search — only its own declaration and a docstring reference
remain). No report uses `HealthStaticInfo` for System Inventory identity
fields.

---

## Platform contract verification (P2 additions)

| Contract | Evidence |
|----------|----------|
| Stable IDs | `motherboard` / `bios` / `cpu` singleton ids; SMBIOS Device Locator for memory; SetupAPI disk instance id for storage; adapter GUID for network (per `smbios_table.cpp`, `storage_collector.cpp`, `network_adapters_collector.cpp` — read only, not modified) |
| `available` | Motherboard/BIOS/memory available when `GetSystemFirmwareTable('RSMB')` returns SMBIOS Type 2/0/17; CPU always available (registry + CPUID); storage/network available on any host with a disk/adapter |
| `unsupported` | Motherboard/BIOS/memory report `unsupported` on hosts without a matching SMBIOS structure (e.g. some VMs) — already covered by `inventory_engine_smoke_test.cpp`'s explicit allow-list for those three domains |
| `partial` / `error` / `access_denied` | Same InventoryEngine-wide status mapping as P0/P1; no new failure paths added for P2 |
| Sectioned UI, not flat dump | `inventory_detail_model.dart` builders always omit empty fields and group by section; verified by code review of every field against `pulse_wire.dart` entry classes |
| Reports SSOT | System Inventory report reuses the exact same section builders as the UI — CSV/JSON/HTML/PDF and the Flutter detail panel cannot drift apart |
| MCP schemas | 6 new tool names registered in `INVENTORY_TOOLS_REGISTERED`; **handlers remain disabled** (`inventoryToolsEnabled: false`); `mcp.self` unit test still asserts `inventoryToolsRegistered` equals the full catalog and `tools` never contains an `inventory.*` name |

---

## Cache / perf from smoke tests

The P2 C++ collectors and `inventory_engine_smoke_test.cpp` (which already
exercises all 16 domains, including force-refresh vs. cache-hit timing) were
committed in a prior session. **This session's sandboxed environment had no
CMake/MSVC toolchain available**, so `inventory_engine_smoke_tests` was
**not rebuilt or re-run here** — no new timing numbers were captured. The
measured P0/P1 numbers from the prior platform report
([r3-inventory-p1-validation-report-2026-08-02.md](r3-inventory-p1-validation-report-2026-08-02.md))
remain the last first-hand cache/perf evidence on record. TTLs for the 6 P2
domains (300 s motherboard/BIOS/CPU/memory, 120 s storage, 60 s network) are
confirmed by reading `*_collector.hpp::kCacheTtlMs` directly and match
ADR-011 exactly (see table above) — this is a static-code check, not a
runtime measurement.

**Action for the next session with a working PulseService build:** run
`inventory_engine_smoke_tests` and append actual P2 fresh-collect /
cache-hit timings to this report (or a follow-up addendum) before checking
the doc 34 "Release build passes" box.

---

## Tests run this session

```
apps/pulse_mcp> npm test
 ✓ test/policy.test.ts (3 tests)
 ✓ test/response.test.ts (2 tests)
 ✓ test/framing.test.ts (2 tests)
 ✓ test/ipc.integration.test.ts (3 tests)
 ✓ test/mcp.self.test.ts (2 tests)
 ✓ test/mcp.integration.test.ts (1 test)
 Test Files  6 passed (6)
      Tests  13 passed (13)

apps/pulse_mcp> npm run build   # tsc -p tsconfig.json — no errors
```

`dart analyze` / `flutter analyze` on the changed inventory/reports files
could **not** be run this session — the sandbox has no Flutter/Dart SDK on
`PATH` (checked `flutter`, `dart`, common install paths). All Dart changes
were reviewed manually against `pulse_wire.dart` field names/types, matched
against the existing widget/report patterns they extend, and kept consistent
with the surrounding code style (records, `switch` exhaustiveness per
`ReportTemplate` case, null-safety on all `has*` wire flags). **Action for
the next session with a Flutter SDK:** run
`flutter analyze lib/presentation/inventory lib/presentation/reports` and
`flutter test` before checking "Release build passes".

---

## Known limitations

1. **Release build not verified this session** — no C++/Flutter toolchain in
   this sandbox. Doc 34's "Release build passes" checkbox stays open.
2. **Device Manager / `msinfo32` spot-check not performed this session** for
   the P2 domains — doc 34's spot-check checkbox stays open. The P0/P1
   spot-check status from the prior report is unaffected.
3. P2 System domains may report `unsupported` on VMs without a full SMBIOS
   table (motherboard/BIOS/memory) — this is ADR-correct, not a bug; no
   fabricated rows are produced.
4. MCP `inventory.*` tools (including the 6 new P2 tools) remain **schema
   only** — handlers stay disabled until the dedicated MCP Inventory
   milestone (doc 34 R5+ track), per ADR-010/ADR-011.
5. `inventoryDomain` on `ReportTemplateX` returns `null` for both
   `hardwareInventory` and `systemInventory` (multi-domain templates); the
   exporter fetches each domain explicitly instead of through the
   single-domain helper — intentional, matches the existing Hardware report
   pattern.
6. System Inventory report CSV/JSON always includes empty arrays/sections
   for domains with 0 entries (e.g. a desktop with no removable/secondary
   storage) rather than omitting the domain — consistent with how Hardware
   (USB/PCI) already behaves; not a new inconsistency.
7. Storage/Network are the only P2 domains with more than one row per
   machine; multi-slot memory modules include unpopulated DIMM slots
   (`populated: false`) rather than hiding them, matching SMBIOS Type 17
   semantics (a real empty slot, not missing data).
8. Bluetooth still legitimately reports `unsupported` (no radio) and Battery
   `unsupported` on desktops without a battery — unchanged from the P1
   report; re-noted here because both remain visible in the same System
   group as the new P2 leaves.

---

## Screenshot checklist (not yet captured — placeholder only)

No screenshots are attached to this report. The following Inventory browser
states should be captured from a running Flutter build in a follow-up pass
(one PNG per row below is enough); **do not fabricate or substitute
placeholder images for these** — leave them absent until captured for real:

### System group (P2 — new this session)

- [ ] Motherboard — list + sectioned detail panel (Identity / Chassis)
- [ ] BIOS — list + sectioned detail panel (Firmware / Capabilities)
- [ ] CPU — list + sectioned detail panel (Identity / Topology / Capabilities)
- [ ] Memory modules — list (populated + empty slots) + sectioned detail panel
- [ ] Storage — list + sectioned detail panel (Identity / Hardware / Capabilities)
- [ ] Network adapters — list + sectioned detail panel (Identity / Network / Driver)

### System group (P1 — already shipped, re-verify sectioned panel still renders)

- [ ] Battery

### Devices group (P0/P1 — unaffected by this session, spot-check only)

- [ ] USB
- [ ] PCI
- [ ] Displays
- [ ] Audio
- [ ] Bluetooth
- [ ] Printers

### Software group (P0 — unaffected by this session, spot-check only)

- [ ] Installed software
- [ ] Drivers
- [ ] Services

### Reports page

- [ ] System Inventory template selected, JSON export
- [ ] System Inventory template, HTML export rendered in a browser
- [ ] System Inventory template, PDF export rendered

---

## Next

1. Maintainer reviews this report alongside the P1 report.
2. Build PulseService + Flutter app on a machine with the toolchain; run
   `inventory_engine_smoke_tests`, `flutter analyze`, and `flutter test`;
   append real numbers/results (or a short addendum report).
3. Capture the screenshot checklist above from that build.
4. Perform the Device Manager / `msinfo32` / `services.msc` spot-check for
   all 16 domains (P0–P2) and record results.
5. Only after 2–4 pass, check the remaining doc 34 R3 boxes ("Release build
   passes", spot-check) and mark **R3 complete**; only then open R4.

---

## Related

- [ADR-011](../decisions/ADR-011-inventory-engine.md)
- [39-inventory-engine-r3.md](../39-inventory-engine-r3.md)
- [34-engineering-roadmap.md](../34-engineering-roadmap.md)
- [33-mcp-bridge.md](../33-mcp-bridge.md)
- [19-windows-apis.md](../19-windows-apis.md)
- [r3-inventory-p1-validation-report-2026-08-02.md](r3-inventory-p1-validation-report-2026-08-02.md)
- [AGENTS.md](../../../AGENTS.md)
