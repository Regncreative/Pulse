import { describe, expect, it } from "vitest";

import { getSharedHealthCache } from "../src/health/cache.js";
import { getSharedIpcSession } from "../src/ipc/session.js";
import { mapCpu } from "../src/health/mappers.js";

/**
 * Soft live test — skips when PulseService is not running.
 */
describe("system.health live IPC", () => {
  it("GetHealthSnapshot via persistent session", async () => {
    const session = getSharedIpcSession();
    try {
      await session.ensureConnected(2000);
    } catch {
      // Soft-skip
      return;
    }
    const health = getSharedHealthCache(session);
    const snap = await health.ensureSnapshot(true);
    expect(snap.sample.unixMs).toBeGreaterThan(0);
    const cpu = mapCpu(snap.sample, snap.info);
    expect(cpu.observedAt).toMatch(/^\d{4}-/);
    // usagePercent may be null only if hasCpuPercent false — normally present.
    expect(
      cpu.usagePercent === null || typeof cpu.usagePercent === "number",
    ).toBe(true);
  });
});
