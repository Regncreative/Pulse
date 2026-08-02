# Inventory spot-check notes (R3)

Read-only comparisons against Windows native tools. Observation only.

## Host

- Date: 2026-08-02
- Smoke: `inventory_engine_smoke_tests` — Motherboard/BIOS/CPU/Memory available;
  Storage partial (unelevated); Network available (3); Bluetooth/Battery unsupported

## Checklist

| Domain | Native tool | Pulse field focus | Result |
|--------|-------------|-------------------|--------|
| Motherboard | msinfo32 → System Summary / BaseBoard | manufacturer, product | Pending manual UI confirm |
| BIOS | msinfo32 → BIOS Version/Date | vendor, version, release date | Pending manual UI confirm |
| CPU | msinfo32 → Processor | name, cores, logical | Smoke: available (1) |
| Memory | msinfo32 → Memory | modules / size / speed | Smoke: available (2) |
| Storage | Disk Management / Device Manager Disk drives | model, bus, size | Smoke: partial (4) |
| Network | ncpa.cpl / Settings → Network | adapters, MAC, IPv4 | Smoke: available (3) |
| USB/PCI | Device Manager | instance presence | Smoke: 18 USB / 43 PCI |
| Services | services.msc | name/state subset | Smoke: truncated list OK |
| Software | Settings → Apps | display name presence | Smoke: truncated list OK |

Screenshots: capture each Inventory browser domain from the running Pulse UI
into `tools/validation-results/inventory-screenshots/` (local; optional in git).
