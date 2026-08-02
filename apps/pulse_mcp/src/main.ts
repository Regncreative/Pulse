#!/usr/bin/env node
/**
 * PulseMCP stdio entry — official MCP transport.
 * Logs go to stderr / JSONL only; stdout is reserved for MCP messages.
 *
 * Modes:
 *   (default)          Full MCP stdio server + status.json heartbeats
 *   --status-daemon    Status/IPC heartbeat only (started by Pulse app)
 */
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { getSharedDiagnosticsCache } from "./diagnostics/cache.js";
import { getSharedHealthCache } from "./health/cache.js";
import { getSharedIpcSession } from "./ipc/session.js";
import { PulseMcpLogger } from "./logging/logger.js";
import { MetricsRegistry } from "./metrics/metrics.js";
import { loadPolicy } from "./policy/policy.js";
import { createPulseMcpServer } from "./server/createServer.js";
import { StatusFileWriter } from "./status/statusFile.js";
import { getSharedTimelineCache } from "./timeline/cache.js";
import { MCP_SERVER_VERSION } from "./version.js";

function wantsStatusDaemon(argv: string[]): boolean {
  return argv.includes("--status-daemon");
}

async function runStatusDaemon(): Promise<void> {
  const logger = new PulseMcpLogger();
  const metrics = new MetricsRegistry();
  const policy = loadPolicy();
  const session = getSharedIpcSession();
  metrics.connectedClients = 0;

  logger.info("PulseMCP status-daemon starting", {
    version: MCP_SERVER_VERSION,
    policyEnabled: policy.enabled,
    milestone: "M7",
  });

  try {
    await session.ensureConnected();
  } catch (err) {
    logger.warn("status-daemon: service not connected yet", {
      error: err instanceof Error ? err.message : String(err),
    });
  }

  const status = new StatusFileWriter({
    metrics,
    policy,
    session,
    logPath: logger.logPath,
    transport: "status-daemon",
    mode: "status-daemon",
    getActiveSubscriptions: () => [],
    clientNames: () => [],
  });
  status.start(2000);

  // Keep process alive; reconnect IPC periodically.
  setInterval(() => {
    void session.ensureConnected().catch(() => undefined);
  }, 5000).unref?.();

  const shutdown = () => {
    status.stop();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

async function runStdioServer(): Promise<void> {
  const logger = new PulseMcpLogger();
  const metrics = new MetricsRegistry();
  const policy = loadPolicy();
  const session = getSharedIpcSession();
  const health = getSharedHealthCache(session);
  const timeline = getSharedTimelineCache(session);
  const diagnostics = getSharedDiagnosticsCache(session);
  const subscriptions = { current: [] as string[] };
  const clientNames: string[] = [];

  logger.info("PulseMCP starting", {
    version: MCP_SERVER_VERSION,
    policyEnabled: policy.enabled,
    policyPath: policy.path,
    logPath: logger.logPath,
    milestone: "M7",
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
    subscriptions,
  });
  const transport = new StdioServerTransport();
  metrics.connectedClients = 1;
  const envClient = process.env.PULSE_MCP_CLIENT_NAME?.trim();
  if (envClient) clientNames.push(envClient);

  const status = new StatusFileWriter({
    metrics,
    policy,
    session,
    logPath: logger.logPath,
    transport: "stdio",
    mode: "stdio",
    getActiveSubscriptions: () => subscriptions.current,
    clientNames: () =>
      clientNames.length > 0 ? [...clientNames] : ["stdio-client"],
  });
  status.start(2000);

  await server.connect(transport);
  logger.info("PulseMCP listening on stdio");
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  if (argv.includes("--cleanup-registrations")) {
    const { cleanupPulseRegistrations } = await import(
      "./uninstall/cleanupRegistrations.js"
    );
    const result = cleanupPulseRegistrations();
    console.error(JSON.stringify({ ok: true, ...result }));
    return;
  }
  if (wantsStatusDaemon(argv)) {
    await runStatusDaemon();
    return;
  }
  await runStdioServer();
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
