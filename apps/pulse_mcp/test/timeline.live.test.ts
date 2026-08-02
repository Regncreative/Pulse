import { describe, expect, it } from "vitest";

import { getSharedIpcSession } from "../src/ipc/session.js";
import {
  getSharedTimelineCache,
  resetTimelineCacheForTests,
} from "../src/timeline/cache.js";
import { mapTimelineEvent } from "../src/timeline/mappers.js";

describe("timeline live IPC", () => {
  it("GetTimelineSnapshot returns events", async () => {
    resetTimelineCacheForTests();
    const session = getSharedIpcSession();
    try {
      await session.ensureConnected(2000);
    } catch {
      return; // soft-skip
    }
    const timeline = getSharedTimelineCache(session);
    const snap = await timeline.getSnapshot({ limit: 50, channel: "System" });
    expect(snap.events.length).toBeGreaterThan(0);
    const mapped = mapTimelineEvent(snap.events[0]!);
    expect(mapped.observedAt).toMatch(/^\d{4}-/);
    expect(typeof mapped.severity).toBe("string");
    expect(mapped.rawXml).toBeUndefined();
  }, 120_000);
});
