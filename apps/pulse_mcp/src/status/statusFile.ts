import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { V1_TOOL_NAMESPACES } from "../catalog/v1.js";
import type { MetricsRegistry } from "../metrics/metrics.js";
import type { McpPolicy } from "../policy/policy.js";
import type { IpcSession } from "../ipc/session.js";
import { MCP_SERVER_VERSION } from "../version.js";

export function defaultStatusPath(): string {
  const base =
    process.env.LOCALAPPDATA ?? path.join(os.homedir(), "AppData", "Local");
  return path.join(base, "Pulse", "mcp", "status.json");
}

export interface StatusWriterOptions {
  metrics: MetricsRegistry;
  policy: McpPolicy;
  session: IpcSession;
  logPath: string;
  transport: "stdio" | "status-daemon";
  mode: "stdio" | "status-daemon";
  getActiveSubscriptions: () => string[];
  clientNames?: () => string[];
  lastReconnectAt?: () => string | null;
}

/** Writes %LOCALAPPDATA%\Pulse\mcp\status.json for Flutter Diagnostics/Settings. */
export class StatusFileWriter {
  private timer: NodeJS.Timeout | null = null;
  private readonly path: string;

  constructor(
    private readonly opts: StatusWriterOptions,
    statusPath = process.env.PULSE_MCP_STATUS_PATH ?? defaultStatusPath(),
  ) {
    this.path = statusPath;
  }

  start(intervalMs = 2000): void {
    this.writeOnce();
    if (this.timer) return;
    this.timer = setInterval(() => this.writeOnce(), intervalMs);
    this.timer.unref?.();
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  writeOnce(): void {
    try {
      const m = this.opts.metrics.snapshot();
      const mem = process.memoryUsage();
      const payload = {
        running: true,
        mode: this.opts.mode,
        version: MCP_SERVER_VERSION,
        uptimeSeconds: m.uptimeSeconds,
        transport: this.opts.transport,
        policyEnabled: this.opts.policy.enabled,
        policyPath: this.opts.policy.path,
        requestsServed: m.requestsServed,
        requestsFailed: m.requestsFailed,
        averageLatencyMs: m.averageLatencyMs,
        averageIpcLatencyMs: m.averageIpcLatencyMs,
        lastRequestAt: m.lastRequestAt,
        lastRequestTool: m.lastRequestTool,
        lastFailureReason: m.lastFailureReason,
        activeSubscriptions: this.opts.getActiveSubscriptions(),
        connectedClients: m.connectedClients,
        clientNames: this.opts.clientNames?.() ?? [],
        namespaces: [...V1_TOOL_NAMESPACES],
        memoryBytes: mem.rss,
        lastReconnectAt: this.opts.lastReconnectAt?.() ?? null,
        servicePipeConnected: this.opts.session.connected,
        serviceVersion: this.opts.session.lastServiceVersion,
        pid: process.pid,
        logPath: this.opts.logPath,
        startedAt: m.startedAt,
        updatedAt: new Date().toISOString(),
      };
      fs.mkdirSync(path.dirname(this.path), { recursive: true });
      const tmp = `${this.path}.tmp`;
      fs.writeFileSync(tmp, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
      fs.renameSync(tmp, this.path);
    } catch {
      // Best-effort UI bridge — never crash the MCP server.
    }
  }
}
