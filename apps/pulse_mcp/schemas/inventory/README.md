# Inventory MCP tool schemas (registered, disabled)

These schemas document the future PulseMCP `inventory.*` tools for domains that
already ship through `GetInventoryDomain` IPC.

| Tool | Domain | Schema | Handler |
|------|--------|--------|---------|
| `inventory.services` | Services | [domain-snapshot.json](domain-snapshot.json) | **Disabled** |
| `inventory.drivers` | Drivers | domain-snapshot.json | **Disabled** |
| `inventory.software` | Software | domain-snapshot.json | **Disabled** |
| `inventory.usb` | USB | domain-snapshot.json | **Disabled** |
| `inventory.pci` | PCI | domain-snapshot.json | **Disabled** |
| `inventory.displays` | Displays | domain-snapshot.json | **Disabled** |
| `inventory.audio` | Audio | domain-snapshot.json | **Disabled** |
| `inventory.bluetooth` | Bluetooth | domain-snapshot.json | **Disabled** |
| `inventory.printers` | Printers | domain-snapshot.json | **Disabled** |
| `inventory.battery` | Battery | domain-snapshot.json | **Disabled** |

Catalog constant: `INVENTORY_TOOLS_REGISTERED` in `src/catalog/v1.ts`.

Active tools remain `V1_TOOLS = ["mcp.self"]` until the MCP Inventory milestone
enables handlers. Calls must never invent rows; payloads stay structured JSON.
