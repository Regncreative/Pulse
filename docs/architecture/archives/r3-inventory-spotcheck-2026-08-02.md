# Inventory spot-check notes (R3)

Read-only comparisons against Windows native tools. Observation only.

**Freeze:** [r3-inventory-engine-frozen-2026-08-02.md](r3-inventory-engine-frozen-2026-08-02.md)  
**Native capture:** [inventory-spotcheck-2026-08-02_11-38-51.md](../../tools/validation-results/inventory-spotcheck-2026-08-02_11-38-51.md)  
**Pulse dump:** [inventory-dump-release.txt](../../tools/validation-results/inventory-dump-release.txt)

## Host

- Date: 2026-08-02
- Machine: SINAN / Windows 11 Pro
- Release smoke: all 16 domains OK (`inventory-smoke-release.txt`)
- Storage: available (4) with models/sizes after Release collector fix
- Memory: unique `bank|locator` ids for dual-channel DIMMs

## Checklist

| Domain | Native tool | Pulse field focus | Result |
|--------|-------------|-------------------|--------|
| Motherboard | msinfo32 / Win32_BaseBoard | manufacturer, product | PASS — ASUSTeK / PRIME B650M-K |
| BIOS | msinfo32 / Win32_BIOS | vendor, version, date | PASS — AMI 3841 / 02/25/2026 |
| CPU | msinfo32 / Win32_Processor | name, cores, logical | PASS — Ryzen 5 7500F 6c/12t |
| Memory | msinfo32 / Win32_PhysicalMemory | modules / size | PASS — 2× Crucial 16GB |
| Storage | Disk Management | model, bus, size | PASS — 4 disks models/sizes |
| Network | ncpa.cpl | adapters, MAC | PASS — Realtek + VBox (+ loopback) |
| USB/PCI | Device Manager | instance presence | PASS — scope deltas documented |
| Displays / Audio / Printers | Device Manager / Get-Printer | presence | PASS |
| Bluetooth / Battery | Device Manager / CIM | absent → unsupported | PASS |
| Services | services.msc | name/state subset | PASS — partial (limit) |
| Software | Settings → Apps (HKLM) | display name presence | PASS — partial (limit) |
| Drivers | Win32_SystemDriver | SCM subset | PASS — partial (limit) |

Screenshots: optional under `tools/validation-results/inventory-screenshots/`
(agent session capture unreliable; dump + native JSON are freeze evidence).
