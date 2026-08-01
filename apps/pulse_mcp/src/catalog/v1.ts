/** v1 registered Observation catalog (grows additively). */
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
