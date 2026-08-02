#!/usr/bin/env node
/**
 * PulseMCP stdio entry — official MCP transport.
 * Logs go to stderr / JSONL only; stdout is reserved for MCP messages.
 */
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { getSharedDiagnosticsCache } from "./diagnostics/cache.js";
import { getSharedHealthCache } from "./health/cache.js";
import { getSharedIpcSession } from "./ipc/session.js";
import { PulseMcpLogger } from "./logging/logger.js";
import { MetricsRegistry } from "./metrics/metrics.js";
import { loadPolicy } from "./policy/policy.js";
import { createPulseMcpServer } from "./server/createServer.js";
import { getSharedTimelineCache } from "./timeline/cache.js";
import { MCP_SERVER_VERSION } from "./version.js";

async function main(): Promise<void> {
  const logger = new PulseMcpLogger();
  const metrics = new MetricsRegistry();
  const policy = loadPolicy();
  const session = getSharedIpcSession();
  const health = getSharedHealthCache(session);
  const timeline = getSharedTimelineCache(session);
  const diagnostics = getSharedDiagnosticsCache(session);

  logger.info("PulseMCP starting", {
    version: MCP_SERVER_VERSION,
    policyEnabled: policy.enabled,
    policyPath: policy.path,
    logPath: logger.logPath,
    milestone: "M6",
  });

  if (!policy.enabled) {
    logger.warn(
      "MCP policy disabled — tools will return POLICY_DISABLED until enabled",
      { policyPath: policy.path },
    );
  }

  const server = createPulseMcpServer({
    metrics,
    policy,
    logger,
    session,
    health,
    timeline,
    diagnostics,
  });
  const transport = new StdioServerTransport();
  metrics.connectedClients = 1;
  await server.connect(transport);
  logger.info("PulseMCP listening on stdio");
}

main().catch((err) => {
  console.error(
    JSON.stringify({
      ts: new Date().toISOString(),
      level: "error",
      message: "PulseMCP fatal",
      error: err instanceof Error ? err.message : String(err),
    }),
  );
  process.exit(1);
});
