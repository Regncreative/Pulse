# R3 — Inventory Engine P1 / platform validation report

**Status:** PASS for P0+P1 platform slice — **P2 not started**  
**Date:** 2026-08-02  
**ADR:** [ADR-011](../decisions/ADR-011-inventory-engine.md) (Accepted)  
**Plan:** [39-inventory-engine-r3.md](../39-inventory-engine-r3.md)  
**Roadmap:** [34-engineering-roadmap.md](../34-engineering-roadmap.md)

Constitution: observation only; Inventory describes; Health measures; no invented rows.

---

## Verdict

**P0 + P1 Inventory platform validated.** Pipeline
Windows APIs → Collectors → InventoryEngine → Cache → IPC → Flutter → Reports → future MCP
is complete for shipped domains. **Do not begin P2 until this report is accepted.**
**Do not begin R4 until every mandatory R3 success metric in doc 34 is checked**
(including P2 System domains and System report SSOT).

---

## Implemented domains

| Priority | Domain | Collector | Stable id | TTL | Status observed (host) |
|----------|--------|-----------|-----------|-----|------------------------|
| P0 | Services | SCM | service name | 60s | `partial` (limit 50 in smoke) |
| P0 | Drivers | SCM drivers | driver service key | 60s | `partial` (limit 50) |
| P0 | Software | Uninstall registry | ProductCode / uninstall key | 300s | `partial` (limit 50) |
| P0 | USB | SetupAPI enum `USB` | instance ID | 60s | `available` (18) |
| P0 | PCI | SetupAPI enum `PCI` | instance ID | 60s | `available` (43) |
| P1 | Displays | SetupAPI class `Monitor` + `EnumDisplayDevicesW` | instance ID | 60s | `available` (2) |
| P1 | Audio | SetupAPI class `Media` | instance ID | 60s | `available` (3) |
| P1 | Bluetooth | SetupAPI class `Bluetooth` | instance ID | 60s | `unsupported` (0) |
| P1 | Printers | `EnumPrintersW` | spooler name | 120s | `available` (1) |
| P1 | Battery | SetupAPI `Battery` + IOCTL; fallback `GetSystemPowerStatus` | instance ID / `system_power` | 30s | `unsupported` (desktop, no battery) |

---

## Remaining domains (P2 — not started)

| Domain | Primary (ADR-011) | TTL |
|--------|-------------------|-----|
| Motherboard | SMBIOS Type 2 | 300s |
| BIOS | SMBIOS Type 0 | 300s |
| CPU | GLPIEx/CPUID helper | 300s |
| Memory modules | SMBIOS Type 17 | 300s |
| Storage | Storage/SetupAPI disks | 120s |
| Network adapters | `GetAdaptersAddresses` | 60s |

---

## Platform contract verification

| Contract | Evidence |
|----------|----------|
| Stable IDs | Collector unit tests reject empty ids |
| Cache generation | Smoke: each domain gets `gen > 0` for available/partial/unsupported |
| Refresh | `force_refresh` path in `InventoryEngine::ServeCachedOrCollect` |
| `available` | USB/PCI/Displays/Audio/Printers on host |
| `unsupported` | Bluetooth (empty), Battery (no system battery) |
| `access_denied` | Mapped from SetupAPI/EnumPrinters; tests SKIP |
| `partial` | Truncation / EnumDisplayDevices enrichment / IOCTL gaps |
| `error` | Invalid domain / API failure paths |
| Lazy start | Collectors never run at service start; only on `GetInventoryDomain` |
| Reports SSOT | Hardware = USB+PCI Inventory; Service/Driver/Software Inventory templates |
| MCP schemas | Registered in `INVENTORY_TOOLS_REGISTERED`; **handlers disabled** |

---

## Cache / refresh / IPC timings

Host: maintainer Windows desktop, Debug Ninja build (`C:\dev\Pulse-service-build-r1`), 2026-08-02.

Source: `inventory_engine_smoke_tests` (limit 50).

| Domain | Fresh collect (ms) | Cache hit (ms) | Generation |
|--------|-------------------:|---------------:|-----------:|
| Services | 22 | 0 | 1 |
| Drivers | 25 | 0 | 2 |
| Software | 2 | 0 | 3 |
| USB | 8 | 0 | 4 |
| PCI | 24 | 0 | 5 |
| Displays | 2 | 0 | 6 |
| Audio | 2 | 0 | 7 |
| Bluetooth | 1 | 0 | 8 |
| Printers | 0 | 0 | 9 |
| Battery | 1 | 0 | 10 |

Notes:

- Cache hit returns the same generation (uniform TTL contract).
- Full IPC round-trip (Flutter ↔ named pipe) not timed in this slice; wire encode/decode covered by `pulse_wire_tests`.
- Incremental `since_generation` diffs still return full snapshots (documented follow-up).

---

## Report validation

| Template | Source of truth | Status |
|----------|-----------------|--------|
| Services | Inventory `services` | Done |
| Drivers | Inventory `drivers` | Done |
| Software | Inventory `software` | Done |
| Hardware | Inventory USB + PCI | Done |
| System | Needs P2 motherboard/BIOS/CPU/memory | **Blocked on P2** |

---

## UI

Inventory page redesigned as a hierarchical browser:

- Groups: System / Devices / Software
- Per domain: search, filter, sort, copy, export (clipboard), refresh, detail panel
- Virtualized `ListView` for large catalogs
- P2 domains visible as reserved leaves (not simple domain chips)

---

## Tests run

```
pulse_wire_tests OK
displays_collector_tests OK count=2
audio_collector_tests OK count=3
bluetooth_collector_tests OK unsupported
printers_collector_tests OK count=1
battery_collector_tests OK unsupported
inventory_engine_smoke_tests OK
```

---

## Known limitations

1. P2 System domains not implemented — System report SSOT incomplete.
2. Bluetooth empty → `unsupported` (ADR-correct); no fabricated radios.
3. Battery on desktop without battery → `unsupported`; IOCTL path validated by compile + empty/unsupported path.
4. Displays may be `partial` when descriptions come from `EnumDisplayDevicesW`.
5. Software omits HKCU/Store (documented ADR limit).
6. Drivers are SCM subset, not Driver Store.
7. MCP inventory tools schemas registered but handlers disabled.
8. Release build / Device Manager spot-check checklist still open for full R3 exit.
9. Inventory UI export currently copies structured text to clipboard (file export can reuse Reports later).

---

## Next

1. Maintainer accepts this P1 platform report.
2. Implement P2 domains one collector per commit.
3. System report → Inventory SSOT.
4. Spot-checks + release build.
5. Only then mark R3 complete and open R4.
