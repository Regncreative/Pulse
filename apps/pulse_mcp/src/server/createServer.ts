import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import type { PulseMcpLogger } from "../logging/logger.js";
import type { MetricsRegistry } from "../metrics/metrics.js";
import type { McpPolicy } from "../policy/policy.js";
import { runMcpSelf } from "../tools/mcp/self.js";
import { MCP_SERVER_VERSION } from "../version.js";

export interface CreateServerOptions {
  metrics: MetricsRegistry;
  policy: McpPolicy;
  logger: PulseMcpLogger;
}

export function createPulseMcpServer(opts: CreateServerOptions): McpServer {
  const server = new McpServer({
    name: "pulse",
    version: MCP_SERVER_VERSION,
  });

  server.registerTool(
    "mcp.self",
    {
      title: "PulseMCP self diagnostics",
      description:
        "Returns PulseMCP versions (MCP protocol, server, Pulse app, PulseService, IPC), capability discovery (tools, resources, subscriptions, report formats, permissions, protocol features), connection health, and local diagnostics. Observation only. Structured JSON — no formatted prose.",
      inputSchema: z.object({}),
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async () => {
      opts.logger.info("tool.call", { tool: "mcp.self" });
      return runMcpSelf({
        metrics: opts.metrics,
        policy: opts.policy,
        logPath: opts.logger.logPath,
        transport: "stdio",
      });
    },
  );

  return server;
}
