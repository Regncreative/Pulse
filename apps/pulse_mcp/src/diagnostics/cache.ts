import type { IpcSession } from "../ipc/session.js";
import { PulseIpcError } from "../ipc/session.js";
import type { DiagnosticsSnapshot } from "./types.js";

const CACHE_FRESH_MS = 2000;

export type DiagnosticsListener = (snap: DiagnosticsSnapshot) => void;

/**
 * Caches GetDiagnosticsSnapshot — no polling unless a resource subscriber
 * explicitly starts the ≤5 s change-detection timer.
 */
export class DiagnosticsCache {
  private snap: DiagnosticsSnapshot | null = null;
  private snapAt = 0;
  private lastNotifyKey: string | null = null;
  private pollTimer: NodeJS.Timeout | null = null;
  private pollSubscribers = 0;
  private listeners = new Set<DiagnosticsListener>();

  constructor(private readonly session: IpcSession) {}

  onChange(listener: DiagnosticsListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async ensureSnapshot(forceRefresh = false): Promise<DiagnosticsSnapshot> {
    const age = Date.now() - this.snapAt;
    if (!forceRefresh && this.snap && age <= CACHE_FRESH_MS) {
      return this.snap;
    }
    return this.fetch();
  }

  async addPollSubscriber(): Promise<void> {
    this.pollSubscribers += 1;
    if (this.pollSubscribers === 1) {
      await this.tick(true);
      this.pollTimer = setInterval(() => {
        void this.tick(false);
      }, 5000);
    }
  }

  async removePollSubscriber(): Promise<void> {
    this.pollSubscribers = Math.max(0, this.pollSubscribers - 1);
    if (this.pollSubscribers === 0 && this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
      this.lastNotifyKey = null;
    }
  }

  private async tick(forceNotify: boolean): Promise<void> {
    try {
      const snap = await this.fetch();
      const key = JSON.stringify(snap);
      if (!forceNotify && this.lastNotifyKey === key) return;
      this.lastNotifyKey = key;
      for (const l of this.listeners) l(snap);
    } catch {
      // Best-effort resource tick.
    }
  }

  private async fetch(): Promise<DiagnosticsSnapshot> {
    const reply = await this.session.request(
      { type: "GetDiagnosticsSnapshot" },
      10_000,
    );
    if (reply.body.type === "ErrorResponse") {
      throw new PulseIpcError(
        reply.body.message || "GetDiagnosticsSnapshot failed",
        "INTERNAL_ERROR",
      );
    }
    if (reply.body.type !== "DiagnosticsSnapshot") {
      throw new PulseIpcError(
        `expected DiagnosticsSnapshot, got ${reply.body.type}`,
        "INTERNAL_ERROR",
      );
    }
    this.snap = reply.body.snapshot;
    this.snapAt = Date.now();
    return this.snap;
  }
}

let shared: DiagnosticsCache | null = null;

export function getSharedDiagnosticsCache(
  session: IpcSession,
): DiagnosticsCache {
  if (!shared) shared = new DiagnosticsCache(session);
  return shared;
}

export function resetDiagnosticsCacheForTests(): void {
  shared = null;
}
