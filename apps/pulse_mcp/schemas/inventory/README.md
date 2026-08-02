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
| `inventory.motherboard` | Motherboard (P2) | domain-snapshot.json | **Disabled** |
| `inventory.bios` | BIOS (P2) | domain-snapshot.json | **Disabled** |
| `inventory.cpu` | CPU (P2) | domain-snapshot.json | **Disabled** |
| `inventory.memory` | Memory modules (P2) | domain-snapshot.json | **Disabled** |
| `inventory.storage` | Storage devices (P2) | domain-snapshot.json | **Disabled** |
| `inventory.network` | Network adapters (P2) | domain-snapshot.json | **Disabled** |

`domain-snapshot.json`'s `domain` enum uses `memory_modules` / `network_adapters`
(snake_case) for the two compound-name P2 domains, matching this schema's
field-naming convention; other domains are single lowercase words.

Catalog constant: `INVENTORY_TOOLS_REGISTERED` in `src/catalog/v1.ts`.

Active tools remain `V1_TOOLS = ["mcp.self"]` until the MCP Inventory milestone
enables handlers. Calls must never invent rows; payloads stay structured JSON.
