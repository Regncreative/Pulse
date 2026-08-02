# R3 — Inventory Engine COMPLETE / FROZEN

**Status:** PASS — R3 **COMPLETE / FROZEN**  
**Date:** 2026-08-02  
**ADR:** [ADR-011](../decisions/ADR-011-inventory-engine.md) (Accepted)  
**Plan:** [39-inventory-engine-r3.md](../39-inventory-engine-r3.md)  
**Roadmap:** [34-engineering-roadmap.md](../34-engineering-roadmap.md)  
**Prior:** [r3-inventory-final-validation-report-2026-08-02.md](r3-inventory-final-validation-report-2026-08-02.md)  
**Native capture:** [inventory-spotcheck-2026-08-02_11-38-51.md](../../tools/validation-results/inventory-spotcheck-2026-08-02_11-38-51.md)  
**Pulse dump:** [inventory-dump-release.txt](../../tools/validation-results/inventory-dump-release.txt)  
**Release smoke:** [inventory-smoke-release.txt](../../tools/validation-results/inventory-smoke-release.txt)

Constitution: observation only; Inventory describes; Health measures; no invented rows.

---

## Verdict

**PASS.** All doc 34 R3 success metrics are evidenced. R3 is **frozen**. **Do not begin R4** until product opens Reports first-class work separately — R3 Inventory platform is closed.

Fixes applied during freeze validation (same day):

1. Memory module stable ids: `bank|device_locator` (dual-channel DIMMs no longer collide on `DIMM 0`).
2. Storage: query-only `CreateFile` + geometry `DiskSize` fallback; SetupAPI description/PROD token when IOCTL model missing; interface path always recorded. Status now `available` with sizes matching Disk Management (~447/931/931/466 GB).

---

## Release builds

| Artifact | Path | Evidence |
|----------|------|----------|
| PulseService Release | `C:\dev\Pulse-service-build-r3-release\PulseService.exe` (~827 KB) | Built `CMAKE_BUILD_TYPE=Release`; installed to `C:\Program Files\Pulse\service\PulseService.exe`; SCM RUNNING |
| Pulse UI Release | `apps/pulse_app/build/windows/x64/runner/Release/Pulse.exe` (via `C:\dev\Pulse-src` junction) | `flutter build windows --release` OK |
| Tests | Release `pulse_wire_tests`, `inventory_engine_smoke_tests` | OK — all 16 domains |

---

## Domain validation matrix (native tools)

Host: SINAN / Windows 11 Pro — 2026-08-02.

| Domain | Pulse status | Pulse evidence | Native source | Match |
|--------|--------------|----------------|---------------|-------|
| Services | partial (limit) | SCM names present | services.msc / Get-Service (296) | PASS (subset/limit documented) |
| Drivers | partial (limit) | SCM driver keys | Win32_SystemDriver (433) | PASS (SCM subset ≠ Driver Store) |
| Software | partial (limit) | Uninstall keys | HKLM Uninstall (143) | PASS (HKCU/Store omitted per ADR) |
| USB | available (18) | SetupAPI USB | Device Manager USB present (12 class) | PASS (Pulse includes hubs/interfaces) |
| PCI | available (43) | SetupAPI PCI | Device Manager PCI | PASS |
| Displays | available (2) | Viseo223DX, ASUS VG247Q1A | Monitor PnP=2 | PASS |
| Audio | available (3) | MEDIA class | MEDIA PnP=3 | PASS |
| Bluetooth | unsupported | No Bluetooth class | Bluetooth PnP=0 | PASS |
| Printers | available (1) | Microsoft Print to PDF | Get-Printer=1 | PASS |
| Battery | unsupported | No system battery | Win32_Battery count=0 | PASS |
| Motherboard | available | ASUSTeK / PRIME B650M-K | msinfo32 / Win32_BaseBoard | PASS exact |
| BIOS | available | AMI 3841 / 02/25/2026 | msinfo32 / Win32_BIOS | PASS exact |
| CPU | available | Ryzen 5 7500F 6c/12t x64 | msinfo32 / Win32_Processor | PASS exact |
| Memory | available (2) | Crucial 16GB ×2 unique ids | Win32_PhysicalMemory count=2 | PASS |
| Storage | available (4) | MSI/Toshiba/ADATA/Samsung + sizes | Disk Management 4 disks | PASS models/sizes |
| Network | available (3) | Realtek + VBox + Loopback | ncpa.cpl (2 hardware; loopback extra) | PASS (loopback intentional GAA) |

---

## Reports SSOT

| Template | Source | HealthStatic bypass? |
|----------|--------|----------------------|
| Service / Driver / Software inventory | Inventory domain | No |
| Hardware inventory | Inventory USB+PCI | No |
| System inventory | Inventory motherboard/BIOS/CPU/memory/storage/network | No — cover identity from Inventory |
| Health snapshot | Health metrics (live) | N/A (not Inventory catalog) |

`healthStaticHardwareRows` remains deprecated helper only; System Inventory tests assert no Health leakage (`report_exporter_test.dart`).

---

## MCP

All 16 `inventory.*` tools registered in `INVENTORY_TOOLS_REGISTERED`; handlers **disabled** until MCP Inventory milestone.

---

## Performance (Release smoke)

All domains cache hit ~0 ms; fresh collect ≤22 ms (services/drivers) on this host. Lazy; requested-domain-only.

---

## Screenshots

Automated desktop capture from the agent session is unreliable (session isolation). Evidence for freeze is the Release dump + native CIM/PnP JSON/MD above.

**Manual screenshot checklist** (optional archive under `tools/validation-results/inventory-screenshots/`):

- [ ] Inventory → System → Motherboard / BIOS / CPU / Memory / Storage / Network / Battery  
- [ ] Inventory → Devices → USB / PCI / Displays / Audio / Bluetooth / Printers  
- [ ] Inventory → Software → Installed software / Drivers / Services  
- [ ] Reports → System inventory export preview  

---

## Known limitations (frozen)

1. Services/Drivers/Software collectors apply documented limits → `partial` when capped.  
2. Software omits HKCU / Store. Drivers = SCM subset.  
3. USB enumerator count can exceed Device Manager “USB” class filter (hubs/MI functions).  
4. Network includes loopback from `GetAdaptersAddresses`.  
5. MCP inventory handlers remain disabled.  
6. Incremental `since_generation` still full snapshot.

---

## Freeze actions completed

- [x] Release PulseService + Release Pulse.exe built and verified  
- [x] Native spot-check recorded  
- [x] Mismatches fixed (memory ids, storage enrichment)  
- [x] Reports SSOT verified  
- [x] Doc 34 R3 success metrics all checked  
- [x] This freeze report archived  

**R3 CLOSED.** R4 must not start without an explicit product decision after this freeze.
