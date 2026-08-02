import type { MetricsRegistry } from "../../metrics/metrics.js";
import type { McpPolicy } from "../../policy/policy.js";
import { failure, success, toMcpToolResult } from "../../response/envelope.js";
import {
  INVENTORY_TOOLS_REGISTERED,
  V1_PERMISSIONS,
  V1_PROTOCOL_FEATURES,
  V1_REPORT_FORMATS,
  V1_RESOURCES,
  V1_SUBSCRIPTIONS,
  V1_TOOLS,
  V1_TOOL_NAMESPACES,
} from "../../catalog/v1.js";
import type { IpcSession } from "../../ipc/session.js";
import {
  IPC_PROTOCOL_VERSION,
  MCP_PROTOCOL_VERSION,
  MCP_SERVER_VERSION,
  PULSE_APP_VERSION,
} from "../../version.js";

export interface McpSelfContext {
  metrics: MetricsRegistry;
  policy: McpPolicy;
  logPath: string;
  transport: "stdio";
  session: IpcSession;
  activeSubscriptions: string[];
}

export async function runMcpSelf(ctx: McpSelfContext) {
  const tool = "mcp.self";
  const started = Date.now();

  if (!ctx.policy.enabled) {
    const body = failure(
      tool,
      "POLICY_DISABLED",
      "Pulse MCP bridge is disabled. Enable it in Pulse Settings, or set policy.json enabled=true.",
      { policyPath: ctx.policy.path },
    );
    ctx.metrics.recordFailure(tool, Date.now() - started, "POLICY_DISABLED");
    return toMcpToolResult(body);
  }

  let ipcError: string | null = null;
  const ipcStarted = Date.now();
  try {
    await ctx.session.ensureConnected();
  } catch (err) {
    ipcError = err instanceof Error ? err.message : String(err);
  }
  const ipcLatencyMs = Date.now() - ipcStarted;

  const metrics = ctx.metrics.snapshot();
  const observedAt = new Date().toISOString();
  const connected = ctx.session.connected;

  const data = {
    enabledPolicy: true,
    uptimeSeconds: metrics.uptimeSeconds,
    transport: ctx.transport,
    versions: {
      mcpProtocol: MCP_PROTOCOL_VERSION,
      mcpServer: MCP_SERVER_VERSION,
      pulseApp: PULSE_APP_VERSION,
      pulseService: ctx.session.lastServiceVersion,
      ipcProtocol: IPC_PROTOCOL_VERSION,
    },
    namespaces: [...V1_TOOL_NAMESPACES],
    capabilities: {
      tools: [...V1_TOOLS],
      resources: [...V1_RESOURCES],
      subscriptions: [...V1_SUBSCRIPTIONS],
      reportFormats: [...V1_REPORT_FORMATS],
      permissions: [...V1_PERMISSIONS],
      protocolFeatures: [...V1_PROTOCOL_FEATURES],
      inventoryToolsRegistered: [...INVENTORY_TOOLS_REGISTERED],
      inventoryToolsEnabled: false,
    },
    connectedClients: Math.max(1, metrics.connectedClients),
    requestsServed: metrics.requestsServed,
    requestsFailed: metrics.requestsFailed,
    averageLatencyMs: metrics.averageLatencyMs,
    averageIpcLatencyMs: metrics.averageIpcLatencyMs,
    lastRequestAt: metrics.lastRequestAt,
    lastRequestTool: metrics.lastRequestTool,
    lastFailureReason: metrics.lastFailureReason,
    activeTools: [...V1_TOOLS],
    activeSubscriptions: ctx.activeSubscriptions,
    logPath: ctx.logPath,
    servicePipeConnected: connected,
    diagnostics: {
      startedAt: metrics.startedAt,
      pid: process.pid,
      policyPath: ctx.policy.path,
      ipcError,
      ipcLatencyMs,
    },
  };

  const body = success(tool, data, {
    observedAt,
    mcpVersion: MCP_SERVER_VERSION,
    ipcProtocolVersion: IPC_PROTOCOL_VERSION,
    serviceVersion: ctx.session.lastServiceVersion,
  });
  ctx.metrics.recordSuccess(tool, Date.now() - started, ipcLatencyMs);
  return toMcpToolResult(body);
}
