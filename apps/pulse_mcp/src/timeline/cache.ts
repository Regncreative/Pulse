import type { IpcSession } from "../ipc/session.js";
import { PulseIpcError } from "../ipc/session.js";
import type { Envelope } from "../ipc/wire.js";
import type { TimelineEvent, TimelineSnapshot } from "./types.js";

const SNAPSHOT_TIMEOUT_MS = 90_000;
const LIVE_RING_MAX = 200;

export type TimelineLiveListener = (event: TimelineEvent) => void;

function mapSnapshotError(message: string, technical: string): PulseIpcError {
  const combined = `${message} ${technical}`.toLowerCase();
  if (
    combined.includes("access") ||
    combined.includes("denied") ||
    combined.includes("evtopenlog") ||
    combined.includes("privilege") ||
    combined.includes("security")
  ) {
    return new PulseIpcError(
      message || "Event Log channel is not accessible",
      "ACCESS_DENIED",
    );
  }
  if (combined.includes("not supported") || combined.includes("unsupported")) {
    return new PulseIpcError(message, "NOT_SUPPORTED");
  }
  return new PulseIpcError(
    message || "GetTimelineSnapshot failed",
    "INTERNAL_ERROR",
  );
}

/**
 * Timeline Engine access via existing IPC — no second collector.
 * Live monitoring starts only while ≥1 MCP resource subscriber is held.
 */
export class TimelineCache {
  private liveSubscribers = 0;
  private liveActive = false;
  private unsubPush: (() => void) | null = null;
  private listeners = new Set<TimelineLiveListener>();
  private recentLive: TimelineEvent[] = [];
  private lastSnapshot: TimelineSnapshot | null = null;

  constructor(private readonly session: IpcSession) {}

  get lastChannelLabel(): string {
    return this.lastSnapshot?.channel ?? "";
  }

  onLiveEvent(listener: TimelineLiveListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  recentLiveEvents(limit = 20): TimelineEvent[] {
    return this.recentLive.slice(-limit);
  }

  async getSnapshot(opts: {
    limit?: number;
    channel?: string;
  } = {}): Promise<TimelineSnapshot> {
    const limit = Math.min(Math.max(1, opts.limit ?? 100), 500);
    // Default "System" → service diagnostics multi-channel set (Flutter parity).
    const channel = opts.channel ?? "System";

    if (channel.toLowerCase() === "security") {
      // Explicit Security-only request — may ACCESS_DENIED under LocalService.
    }

    const reply = await this.session.request(
      { type: "GetTimelineSnapshot", limit, channel },
      SNAPSHOT_TIMEOUT_MS,
    );

    if (reply.body.type === "ErrorResponse") {
      throw mapSnapshotError(
        reply.body.message,
        reply.body.technicalDetail,
      );
    }
    if (reply.body.type !== "TimelineSnapshot") {
      throw new PulseIpcError(
        `expected TimelineSnapshot, got ${reply.body.type}`,
        "INTERNAL_ERROR",
      );
    }
    this.lastSnapshot = reply.body.snapshot;
    return reply.body.snapshot;
  }

  async getEventDetail(
    channel: string,
    recordId: number,
  ): Promise<TimelineEvent | null> {
    const reply = await this.session.request(
      { type: "GetTimelineEventDetail", channel, recordId },
      30_000,
    );
    if (reply.body.type === "ErrorResponse") {
      throw mapSnapshotError(
        reply.body.message,
        reply.body.technicalDetail,
      );
    }
    if (reply.body.type !== "TimelineEventDetail") {
      throw new PulseIpcError(
        `expected TimelineEventDetail, got ${reply.body.type}`,
        "INTERNAL_ERROR",
      );
    }
    if (!reply.body.detail.found || !reply.body.detail.event) return null;
    return reply.body.detail.event;
  }

  async addLiveSubscriber(): Promise<void> {
    this.liveSubscribers += 1;
    if (this.liveSubscribers === 1) {
      await this.startLive();
    }
  }

  async removeLiveSubscriber(): Promise<void> {
    this.liveSubscribers = Math.max(0, this.liveSubscribers - 1);
    if (this.liveSubscribers === 0) {
      await this.stopLive();
    }
  }

  private async startLive(): Promise<void> {
    if (this.liveActive) return;
    await this.session.ensureConnected();
    if (!this.unsubPush) {
      this.unsubPush = this.session.onPush((env: Envelope) => {
        if (env.body.type === "LiveTimelineEvent") {
          this.pushLive(env.body.event);
        }
      });
    }
    const reply = await this.session.request(
      { type: "StartLiveMonitoring", channel: "System" },
      10_000,
    );
    if (reply.body.type === "ErrorResponse" && reply.body.code !== 0) {
      throw mapSnapshotError(
        reply.body.message,
        reply.body.technicalDetail,
      );
    }
    this.liveActive = true;
  }

  private async stopLive(): Promise<void> {
    if (!this.liveActive) return;
    this.liveActive = false;
    try {
      if (this.session.connected) {
        await this.session.request({ type: "StopLiveMonitoring" }, 5_000);
      }
    } catch {
      // Best-effort.
    }
  }

  private pushLive(event: TimelineEvent): void {
    this.recentLive.push(event);
    if (this.recentLive.length > LIVE_RING_MAX) {
      this.recentLive = this.recentLive.slice(-LIVE_RING_MAX);
    }
    for (const l of this.listeners) l(event);
  }
}

let sharedTimeline: TimelineCache | null = null;

export function getSharedTimelineCache(session: IpcSession): TimelineCache {
  if (!sharedTimeline) sharedTimeline = new TimelineCache(session);
  return sharedTimeline;
}

export function resetTimelineCacheForTests(): void {
  sharedTimeline = null;
}
