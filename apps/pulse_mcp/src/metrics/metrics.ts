export interface MetricsSnapshot {
  startedAt: string;
  uptimeSeconds: number;
  requestsServed: number;
  requestsFailed: number;
  averageLatencyMs: number;
  averageIpcLatencyMs: number;
  lastRequestAt: string | null;
  lastRequestTool: string | null;
  lastFailureReason: string | null;
  connectedClients: number;
}

export class MetricsRegistry {
  readonly startedAt = new Date();
  private requestsServed = 0;
  private requestsFailed = 0;
  private latencySumMs = 0;
  private ipcLatencySumMs = 0;
  private ipcLatencyCount = 0;
  private lastRequestAt: string | null = null;
  private lastRequestTool: string | null = null;
  private lastFailureReason: string | null = null;
  connectedClients = 0;

  recordSuccess(
    tool: string,
    latencyMs: number,
    ipcLatencyMs: number | null = null,
  ): void {
    this.requestsServed += 1;
    this.latencySumMs += latencyMs;
    if (ipcLatencyMs != null) {
      this.ipcLatencySumMs += ipcLatencyMs;
      this.ipcLatencyCount += 1;
    }
    this.lastRequestAt = new Date().toISOString();
    this.lastRequestTool = tool;
  }

  recordFailure(
    tool: string,
    latencyMs: number,
    reason?: string,
    ipcLatencyMs: number | null = null,
  ): void {
    this.requestsServed += 1;
    this.requestsFailed += 1;
    this.latencySumMs += latencyMs;
    if (ipcLatencyMs != null) {
      this.ipcLatencySumMs += ipcLatencyMs;
      this.ipcLatencyCount += 1;
    }
    this.lastRequestAt = new Date().toISOString();
    this.lastRequestTool = tool;
    this.lastFailureReason = reason ?? "unknown";
  }

  snapshot(): MetricsSnapshot {
    const total = this.requestsServed;
    return {
      startedAt: this.startedAt.toISOString(),
      uptimeSeconds: Math.floor((Date.now() - this.startedAt.getTime()) / 1000),
      requestsServed: this.requestsServed,
      requestsFailed: this.requestsFailed,
      averageLatencyMs: total === 0 ? 0 : Math.round(this.latencySumMs / total),
      averageIpcLatencyMs:
        this.ipcLatencyCount === 0
          ? 0
          : Math.round(this.ipcLatencySumMs / this.ipcLatencyCount),
      lastRequestAt: this.lastRequestAt,
      lastRequestTool: this.lastRequestTool,
      lastFailureReason: this.lastFailureReason,
      connectedClients: this.connectedClients,
    };
  }
}
