import type { MetricsRegistry } from "../../metrics/metrics.js";
import type { McpPolicy } from "../../policy/policy.js";
import { failure, success, toMcpToolResult } from "../../response/envelope.js";
import {
  V1_PERMISSIONS,
  V1_PROTOCOL_FEATURES,
  V1_REPORT_FORMATS,
  V1_RESOURCES,
  V1_SUBSCRIPTIONS,
  V1_TOOLS,
} from "../../catalog/v1.js";
import { ipcHello } from "../../ipc/client.js";
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
    ctx.metrics.recordFailure(tool, Date.now() - started);
    return toMcpToolResult(body);
  }

  const hello = await ipcHello();
  const metrics = ctx.metrics.snapshot();
  const observedAt = new Date().toISOString();

  const data = {
    enabledPolicy: true,
    uptimeSeconds: metrics.uptimeSeconds,
    transport: ctx.transport,
    versions: {
      mcpProtocol: MCP_PROTOCOL_VERSION,
      mcpServer: MCP_SERVER_VERSION,
      pulseApp: PULSE_APP_VERSION,
      pulseService: hello.serviceVersion,
      ipcProtocol: hello.ipcProtocolVersion || IPC_PROTOCOL_VERSION,
    },
    capabilities: {
      tools: [...V1_TOOLS],
      resources: [...V1_RESOURCES],
      subscriptions: [...V1_SUBSCRIPTIONS],
      reportFormats: [...V1_REPORT_FORMATS],
      permissions: [...V1_PERMISSIONS],
      protocolFeatures: [...V1_PROTOCOL_FEATURES],
    },
    connectedClients: Math.max(1, metrics.connectedClients),
    requestsServed: metrics.requestsServed,
    requestsFailed: metrics.requestsFailed,
    averageLatencyMs: metrics.averageLatencyMs,
    lastRequestAt: metrics.lastRequestAt,
    lastRequestTool: metrics.lastRequestTool,
    activeTools: [...V1_TOOLS],
    activeSubscriptions: [...V1_SUBSCRIPTIONS],
    logPath: ctx.logPath,
    servicePipeConnected: hello.connected,
    diagnostics: {
      startedAt: metrics.startedAt,
      pid: process.pid,
      policyPath: ctx.policy.path,
      ipcError: hello.connected ? null : (hello.error ?? "unavailable"),
    },
  };

  const body = success(tool, data, {
    observedAt,
    mcpVersion: MCP_SERVER_VERSION,
    ipcProtocolVersion: IPC_PROTOCOL_VERSION,
    serviceVersion: hello.serviceVersion,
  });
  ctx.metrics.recordSuccess(tool, Date.now() - started);
  return toMcpToolResult(body);
}
