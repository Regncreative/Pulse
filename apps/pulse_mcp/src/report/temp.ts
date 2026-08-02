import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const DEFAULT_TTL_MS = 60 * 60 * 1000; // 1 hour
const CLEANUP_INTERVAL_MS = 5 * 60 * 1000;

export interface TempReportEntry {
  reportId: string;
  path: string;
  createdAtMs: number;
}

/**
 * Tracks temporary MCP report files and deletes them after TTL.
 */
export class TempReportStore {
  private readonly entries = new Map<string, TempReportEntry>();
  private timer: NodeJS.Timeout | null = null;
  private readonly root: string;
  private readonly ttlMs: number;

  constructor(opts?: { root?: string; ttlMs?: number }) {
    this.root =
      opts?.root ?? path.join(os.tmpdir(), "Pulse", "mcp-reports");
    this.ttlMs = opts?.ttlMs ?? DEFAULT_TTL_MS;
  }

  async ensureRoot(): Promise<string> {
    await fs.mkdir(this.root, { recursive: true });
    return this.root;
  }

  track(reportId: string, filePath: string): void {
    this.entries.set(reportId, {
      reportId,
      path: filePath,
      createdAtMs: Date.now(),
    });
    this.ensureTimer();
  }

  list(): TempReportEntry[] {
    return [...this.entries.values()];
  }

  async cleanupExpired(now = Date.now()): Promise<number> {
    let removed = 0;
    for (const [id, entry] of this.entries) {
      if (now - entry.createdAtMs < this.ttlMs) continue;
      try {
        await fs.unlink(entry.path);
      } catch {
        // Already gone.
      }
      this.entries.delete(id);
      removed += 1;
    }
    if (this.entries.size === 0 && this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    return removed;
  }

  /** Test helper — force-expire all tracked temps. */
  async cleanupAll(): Promise<number> {
    let removed = 0;
    for (const [id, entry] of this.entries) {
      try {
        await fs.unlink(entry.path);
      } catch {
        // ignore
      }
      this.entries.delete(id);
      removed += 1;
    }
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    return removed;
  }

  private ensureTimer(): void {
    if (this.timer) return;
    this.timer = setInterval(() => {
      void this.cleanupExpired();
    }, CLEANUP_INTERVAL_MS);
    this.timer.unref?.();
  }
}

let shared: TempReportStore | null = null;

export function getSharedTempReportStore(): TempReportStore {
  if (!shared) shared = new TempReportStore();
  return shared;
}

export function resetTempReportStoreForTests(): void {
  shared = null;
}
