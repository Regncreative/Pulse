/**
 * MCP wire tool names.
 *
 * Claude Desktop / Anthropic FrontendRemoteMcpToolDefinition require
 * `^[a-zA-Z0-9_-]{1,64}$` — dots are rejected. Logical namespaces stay
 * system/process/timeline/…; wire form uses underscores (`system_cpu`).
 */

/** Registered Inventory MCP tools — schemas exist, handlers disabled until MCP Inventory milestone. */
export const INVENTORY_TOOLS_REGISTERED = [
  "inventory_services",
  "inventory_drivers",
  "inventory_software",
  "inventory_usb",
  "inventory_pci",
  "inventory_displays",
  "inventory_audio",
  "inventory_bluetooth",
  "inventory_printers",
  "inventory_battery",
  "inventory_motherboard",
  "inventory_bios",
  "inventory_cpu",
  "inventory_memory",
  "inventory_storage",
  "inventory_network",
] as const;

/** Active v1 tools (handlers registered). */
export const V1_TOOLS = [
  "mcp_self",
  "system_health",
  "system_cpu",
  "system_memory",
  "system_gpu",
  "system_storage",
  "system_network",
  "process_list",
  "process_search",
  "process_details",
  "timeline_list",
  "timeline_search",
  "diagnostics_snapshot",
  "service_status",
  "report_export",
] as const;

export const V1_TOOL_NAMESPACES = [
  "mcp",
  "system",
  "process",
  "timeline",
  "diagnostics",
  "service",
  "report",
] as const;

export const V1_RESOURCES = [
  "pulse://system/cpu",
  "pulse://system/memory",
  "pulse://system/gpu",
  "pulse://system/network",
  "pulse://system/health",
  "pulse://timeline/live",
  "pulse://diagnostics/snapshot",
  "pulse://mcp/status",
] as const;

/** Subscribable resource URIs (health + timeline + diagnostics + mcp status). */
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

/** Normalize legacy dotted names (`system.cpu`) to wire form (`system_cpu`). */
export function normalizeToolName(name: string): string {
  return name.replace(/\./g, "_");
}
