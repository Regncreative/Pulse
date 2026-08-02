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
  "inventory.motherboard",
  "inventory.bios",
  "inventory.cpu",
  "inventory.memory",
  "inventory.storage",
  "inventory.network",
] as const;

/** Active v1 tools (handlers registered). */
export const V1_TOOLS = [
  "mcp.self",
  "system.health",
  "system.cpu",
  "system.memory",
  "system.gpu",
  "system.storage",
  "system.network",
  "process.list",
  "process.search",
  "process.details",
  "timeline.list",
  "timeline.search",
] as const;

export const V1_TOOL_NAMESPACES = [
  "mcp",
  "system",
  "process",
  "timeline",
] as const;

export const V1_RESOURCES = [
  "pulse://system/cpu",
  "pulse://system/memory",
  "pulse://system/gpu",
  "pulse://system/network",
  "pulse://system/health",
  "pulse://timeline/live",
] as const;

/** Subscribable resource URIs (health + timeline live). */
export const V1_SUBSCRIPTIONS = [...V1_RESOURCES] as const;

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
  "resources",
  "resource_subscriptions",
  "structured_json",
  "stdio",
  "capability_discovery",
] as const;

export type ToolName = (typeof V1_TOOLS)[number];
export type InventoryToolName = (typeof INVENTORY_TOOLS_REGISTERED)[number];
