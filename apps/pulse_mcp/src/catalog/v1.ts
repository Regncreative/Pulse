/** Registered Inventory MCP tools — schemas exist, handlers disabled until MCP Inventory milestone. */
export const INVENTORY_TOOLS_REGISTERED = [
  "inventory.services",
  "inventory.drivers",
  "inventory.software",
  "inventory.usb",
  "inventory.pci",
  "inventory.displays",
  "inventory.audio",
  "inventory.bluetooth",
  "inventory.printers",
  "inventory.battery",
] as const;

/** Active v1 tools (handlers registered). Inventory tools are not active yet. */
export const V1_TOOLS = ["mcp.self"] as const;

export const V1_RESOURCES: string[] = [];

export const V1_SUBSCRIPTIONS: string[] = [];

export const V1_REPORT_FORMATS = [
  "json",
  "html",
  "pdf",
  "markdown",
  "csv",
] as const;

export const V1_PERMISSIONS = ["observation"] as const;

export const V1_PROTOCOL_FEATURES = [
  "tools",
  "structured_json",
  "stdio",
  "capability_discovery",
] as const;

export type ToolName = (typeof V1_TOOLS)[number];
export type InventoryToolName = (typeof INVENTORY_TOOLS_REGISTERED)[number];
