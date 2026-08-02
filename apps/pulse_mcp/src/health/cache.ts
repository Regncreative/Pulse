import type { IpcSession } from "../ipc/session.js";
import { PulseIpcError } from "../ipc/session.js";
import type { Envelope } from "../ipc/wire.js";
import type {
  HealthProcessEntry,
  HealthProcessInventoryUpdate,
  HealthSample,
  HealthSnapshot,
  HealthStaticInfo,
  ProcessDetails,
} from "./types.js";
import { emptySample, emptyStaticInfo } from "./types.js";

const CACHE_FRESH_MS = 2000;
const INVENTORY_WAIT_MS = 4000;

export type HealthListener = (sample: HealthSample) => void;

/**
 * Caches Health Engine data from IPC. Starts service health monitoring only
 * while MCP resource subscribers or inventory holds are active — no polling.
 */
export class HealthCache {
  private sample: HealthSample = emptySample();
  private info: HealthStaticInfo = emptyStaticInfo();
  private sampleAt = 0;
  private monitoring = false;
  private subscriberCount = 0;
  private inventoryHold = 0;
  private listeners = new Set<HealthListener>();
  private unsubPush: (() => void) | null = null;
  private byPid = new Map<number, HealthProcessEntry>();
  private inventorySeq = 0;
  private inventoryAt = 0;
  private inventoryWaiters: Array<() => void> = [];

  constructor(private readonly session: IpcSession) {}

  get staticInfo(): HealthStaticInfo {
    return this.info;
  }

  get latestSample(): HealthSample | null {
    return this.sampleAt > 0 ? this.sample : null;
  }

  get processCount(): number {
    return this.byPid.size;
  }

  onSample(listener: HealthListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Resource subscription refcount — starts/stops HealthUpdate stream. */
  async addSubscriber(): Promise<void> {
    this.subscriberCount += 1;
    if (this.subscriberCount + this.inventoryHold === 1) {
      await this.startMonitoring();
    }
  }

  async removeSubscriber(): Promise<void> {
    this.subscriberCount = Math.max(0, this.subscriberCount - 1);
    if (this.subscriberCount === 0 && this.inventoryHold === 0) {
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

  /**
   * Ensure HealthUpdate stream is running and process inventory is populated.
   * Holds monitoring for the duration of `work`, then releases.
   */
  async withInventory<T>(work: () => Promise<T>): Promise<T> {
    this.inventoryHold += 1;
    try {
      if (!this.monitoring) {
        await this.startMonitoring();
      }
      await this.waitForInventory();
      return await work();
    } finally {
      this.inventoryHold = Math.max(0, this.inventoryHold - 1);
      if (this.inventoryHold === 0 && this.subscriberCount === 0) {
        await this.stopMonitoring();
      }
    }
  }

  listProcesses(): HealthProcessEntry[] {
    return [...this.byPid.values()];
  }

  getProcess(pid: number): HealthProcessEntry | undefined {
    return this.byPid.get(pid);
  }

  async getProcessDetails(pid: number): Promise<ProcessDetails> {
    if (!Number.isInteger(pid) || pid <= 0) {
      throw new PulseIpcError(
        "pid must be a positive integer",
        "INVALID_ARGUMENT",
      );
    }
    const reply = await this.session.request(
      { type: "GetProcessDetails", pid },
      5000,
    );
    if (reply.body.type === "ErrorResponse") {
      const msg = reply.body.message || "GetProcessDetails failed";
      if (/not found|no such process|does not exist/i.test(msg)) {
        throw new PulseIpcError(msg, "PROCESS_NOT_FOUND");
      }
      throw new PulseIpcError(msg, "INTERNAL_ERROR");
    }
    if (reply.body.type !== "ProcessDetails") {
      throw new PulseIpcError(
        `expected ProcessDetails, got ${reply.body.type}`,
        "INTERNAL_ERROR",
      );
    }
    const details = reply.body.details;
    // Service returns an empty ProcessDetails shell when the pid is unknown.
    if (
      !details.name &&
      !details.hasPath &&
      !details.hasCommandLine &&
      !this.byPid.has(pid)
    ) {
      throw new PulseIpcError(
        `Process ${pid} was not found`,
        "PROCESS_NOT_FOUND",
      );
    }
    return details;
  }

  private async waitForInventory(): Promise<void> {
    if (this.byPid.size > 0 && Date.now() - this.inventoryAt < 15_000) {
      return;
    }
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        cleanup();
        if (this.byPid.size > 0) resolve();
        else
          reject(
            new PulseIpcError(
              "Timed out waiting for process inventory from PulseService",
              "TIMEOUT",
            ),
          );
      }, INVENTORY_WAIT_MS);
      const onReady = () => {
        cleanup();
        resolve();
      };
      const cleanup = () => {
        clearTimeout(timer);
        this.inventoryWaiters = this.inventoryWaiters.filter((w) => w !== onReady);
      };
      this.inventoryWaiters.push(onReady);
      // Inventory may have arrived between the early check and waiter registration.
      if (this.byPid.size > 0) {
        cleanup();
        resolve();
      }
    });
  }

  private notifyInventoryWaiters(): void {
    const waiters = this.inventoryWaiters;
    this.inventoryWaiters = [];
    for (const w of waiters) w();
  }

  private async fetchSnapshot(): Promise<HealthSnapshot> {
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
    return { info: this.info, sample: this.sample };
  }

  private applySnapshot(snap: HealthSnapshot): void {
    this.info = snap.info;
    this.sample = snap.sample;
    this.sampleAt = Date.now();
    for (const l of this.listeners) l(this.sample);
  }

  private applyUpdate(
    sample: HealthSample,
    inventory: HealthProcessInventoryUpdate | null,
  ): void {
    this.sample = sample;
    this.sampleAt = Date.now();
    if (inventory) this.applyInventory(inventory);
    for (const l of this.listeners) l(this.sample);
  }

  private applyInventory(update: HealthProcessInventoryUpdate): void {
    this.inventorySeq = update.seq;
    this.inventoryAt = Date.now();
    if (update.fullResync) {
      this.byPid.clear();
    }
    for (const entry of update.upserts) {
      const prev = this.byPid.get(entry.pid);
      if (
        prev &&
        prev.hasCreateTime &&
        entry.hasCreateTime &&
        prev.createTimeUnixMs !== entry.createTimeUnixMs
      ) {
        // PID recycled — replace identity.
      }
      this.byPid.set(entry.pid, entry);
    }
    for (const pid of update.removedPids) {
      this.byPid.delete(pid);
    }
    if (this.byPid.size > 0) this.notifyInventoryWaiters();
  }

  private async startMonitoring(): Promise<void> {
    if (this.monitoring) return;
    await this.session.ensureConnected();
    if (!this.unsubPush) {
      this.unsubPush = this.session.onPush((env: Envelope) => {
        if (env.body.type === "HealthUpdate") {
          this.applyUpdate(env.body.sample, env.body.inventory);
        }
      });
    }
    try {
      await this.fetchSnapshot();
    } catch {
      // Monitoring may still deliver updates.
    }
    const reply = await this.session.request(
      { type: "StartHealthMonitoring" },
      5000,
    );
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
        await this.session.request({ type: "StopHealthMonitoring" }, 3000);
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
