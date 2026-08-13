# Upgrade notes

## To 1.1.0

- Installer: `Pulse-Setup-1.1.0-windows-x64.exe`
- Product stamp is **`1.1.0`** (UI, PulseService, PulseMCP)
- After upgrading from **1.0.0**:
  1. Confirm Diagnostics → App / Service show **1.1.0**
  2. Open **Assistant** from the sidebar to select Local AI provider/model if desired
  3. If you use MCP: **Settings → AI Integration → Unregister → Register**

## To 1.0.0 (stable)

- Installer: `Pulse-Setup-1.0.0-windows-x64.exe`
- Product stamp is **`1.0.0`** (no beta label)
- PulseMCP **1.0.0** (bundled private Node — no system Node.js)
- After upgrading from any **0.3.x-beta**:
  1. Confirm PulseService is Running (Diagnostics → Service)
  2. **Settings → AI Integration → Unregister → Register** so Cursor / Claude point at the new `PulseMCP.exe`
  3. Fully quit and reopen AI clients

## Historical betas

### 0.3.2-beta

- PulseMCP `0.7.2`: named-pipe instance limit 32, Claude Store config path, underscore MCP tool wire names

### 0.3.1-beta

- PulseMCP private Node runtime — **no system Node.js**. Re-Register after upgrading from **0.3.0-beta**

### 0.3.0-beta

- MCP M2–M7 productization (AI Integration page, policy file, registration)

Full notes: [docs/releases/](../releases/).
