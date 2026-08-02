import type { IpcSession } from "../ipc/session.js";
import { PulseIpcError } from "../ipc/session.js";
import type { Envelope } from "../ipc/wire.js";
import type { HealthSample, HealthSnapshot, HealthStaticInfo } from "./types.js";
import { emptySample, emptyStaticInfo } from "./types.js";

const CACHE_FRESH_MS = 2000;

export type HealthListener = (sample: HealthSample) => void;

/**
 * Caches Health Engine data from IPC. Starts service health monitoring only
 * while MCP resource subscribers (or explicit holds) are active — no polling.
 */
export class HealthCache {
  private sample: HealthSample = emptySample();
  private info: HealthStaticInfo = emptyStaticInfo();
  private sampleAt = 0;
  private monitoring = false;
  private subscriberCount = 0;
  private listeners = new Set<HealthListener>();
  private unsubPush: (() => void) | null = null;

  constructor(private readonly session: IpcSession) {}

  get staticInfo(): HealthStaticInfo {
    return this.info;
  }

  get latestSample(): HealthSample | null {
    return this.sampleAt > 0 ? this.sample : null;
  }

  onSample(listener: HealthListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Resource subscription refcount — starts/stops HealthUpdate stream. */
  async addSubscriber(): Promise<void> {
    this.subscriberCount += 1;
    if (this.subscriberCount === 1) {
      await this.startMonitoring();
    }
  }

  async removeSubscriber(): Promise<void> {
    this.subscriberCount = Math.max(0, this.subscriberCount - 1);
    if (this.subscriberCount === 0) {
      await this.stopMonitoring();
    }
  }

  /**
   * Prefer cached sample when fresh; otherwise one GetHealthSnapshot RPC.
   * Never opens a polling loop.
   */
  async ensureSnapshot(forceRefresh = false): Promise<HealthSnapshot> {
    const age = Date.now() - this.sampleAt;
    if (
      !forceRefresh &&
      this.sampleAt > 0 &&
      (age <= CACHE_FRESH_MS || this.monitoring)
    ) {
      return { info: this.info, sample: this.sample };
    }
    return this.fetchSnapshot();
  }

  private async fetchSnapshot(): Promise<HealthSnapshot> {
    const started = Date.now();
    const reply = await this.session.request(
      { type: "GetHealthSnapshot" },
      5000,
    );
    if (reply.body.type === "ErrorResponse") {
      throw new PulseIpcError(
        reply.body.message || "GetHealthSnapshot failed",
        "INTERNAL_ERROR",
      );
    }
    if (reply.body.type !== "HealthSnapshot") {
      throw new PulseIpcError(
        `expected HealthSnapshot, got ${reply.body.type}`,
        "INTERNAL_ERROR",
      );
    }
    this.applySnapshot(reply.body.snapshot);
    void started;
    return { info: this.info, sample: this.sample };
  }

  private applySnapshot(snap: HealthSnapshot): void {
    this.info = snap.info;
    this.sample = snap.sample;
    this.sampleAt = Date.now();
    for (const l of this.listeners) l(this.sample);
  }

  private applyUpdate(sample: HealthSample): void {
    this.sample = sample;
    this.sampleAt = Date.now();
    for (const l of this.listeners) l(this.sample);
  }

  private async startMonitoring(): Promise<void> {
    if (this.monitoring) return;
    await this.session.ensureConnected();
    if (!this.unsubPush) {
      this.unsubPush = this.session.onPush((env: Envelope) => {
        if (env.body.type === "HealthUpdate") {
          this.applyUpdate(env.body.sample);
        }
      });
    }
    // Warm cache with a snapshot (also loads static info).
    try {
      await this.fetchSnapshot();
    } catch {
      // Monitoring may still deliver updates.
    }
    const reply = await this.session.request(
      { type: "StartHealthMonitoring" },
      5000,
    );
    // Service ACKs with ErrorResponse code=0 (same as Flutter client).
    if (reply.body.type === "ErrorResponse" && reply.body.code !== 0) {
      throw new PulseIpcError(
        reply.body.message || "StartHealthMonitoring failed",
        "INTERNAL_ERROR",
      );
    }
    this.monitoring = true;
  }

  private async stopMonitoring(): Promise<void> {
    if (!this.monitoring) return;
    this.monitoring = false;
    try {
      if (this.session.connected) {
        const reply = await this.session.request(
          { type: "StopHealthMonitoring" },
          3000,
        );
        if (reply.body.type === "ErrorResponse" && reply.body.code !== 0) {
          // Best-effort; still clear local monitoring flag.
        }
      }
    } catch {
      // Best-effort stop.
    }
  }
}

let sharedCache: HealthCache | null = null;

export function getSharedHealthCache(session: IpcSession): HealthCache {
  if (!sharedCache) sharedCache = new HealthCache(session);
  return sharedCache;
}

export function resetHealthCacheForTests(): void {
  sharedCache = null;
}
