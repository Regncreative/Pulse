export interface MetricsSnapshot {
  startedAt: string;
  uptimeSeconds: number;
  requestsServed: number;
  requestsFailed: number;
  averageLatencyMs: number;
  lastRequestAt: string | null;
  lastRequestTool: string | null;
  connectedClients: number;
}

export class MetricsRegistry {
  readonly startedAt = new Date();
  private requestsServed = 0;
  private requestsFailed = 0;
  private latencySumMs = 0;
  private lastRequestAt: string | null = null;
  private lastRequestTool: string | null = null;
  connectedClients = 0;

  recordSuccess(tool: string, latencyMs: number): void {
    this.requestsServed += 1;
    this.latencySumMs += latencyMs;
    this.lastRequestAt = new Date().toISOString();
    this.lastRequestTool = tool;
  }

  recordFailure(tool: string, latencyMs: number): void {
    this.requestsServed += 1;
    this.requestsFailed += 1;
    this.latencySumMs += latencyMs;
    this.lastRequestAt = new Date().toISOString();
    this.lastRequestTool = tool;
  }

  snapshot(): MetricsSnapshot {
    const total = this.requestsServed;
    return {
      startedAt: this.startedAt.toISOString(),
      uptimeSeconds: Math.floor((Date.now() - this.startedAt.getTime()) / 1000),
      requestsServed: this.requestsServed,
      requestsFailed: this.requestsFailed,
      averageLatencyMs: total === 0 ? 0 : Math.round(this.latencySumMs / total),
      lastRequestAt: this.lastRequestAt,
      lastRequestTool: this.lastRequestTool,
      connectedClients: this.connectedClients,
    };
  }
}
