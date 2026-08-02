import { describe, expect, it } from "vitest";

import { getSharedHealthCache, resetHealthCacheForTests } from "../src/health/cache.js";
import { IpcSession } from "../src/ipc/session.js";
import { filterSortProcesses, mapProcessDetails } from "../src/process/mappers.js";

/**
 * Soft live test — skips when PulseService is down.
 */
describe("process live IPC", () => {
  it("lists processes and fetches details for current pid", async () => {
    resetHealthCacheForTests();
    const session = new IpcSession();
    try {
      await session.ensureConnected();
    } catch {
      return; // soft-skip
    }
    const health = getSharedHealthCache(session);
    try {
      const result = await health.withInventory(async () => {
        const list = filterSortProcesses(health.listProcesses(), {
          limit: 20,
          sortBy: "cpu",
        });
        expect(list.count).toBeGreaterThan(0);
        const selfPid = process.pid;
        const details = await health.getProcessDetails(selfPid);
        expect(details.pid).toBe(selfPid);
        const mapped = mapProcessDetails(details, health.getProcess(selfPid));
        expect(mapped.pid).toBe(selfPid);
        expect(mapped.name).toBeTruthy();
        return list;
      });
      expect(result.count).toBeGreaterThan(0);
    } finally {
      await session.close();
      resetHealthCacheForTests();
    }
  }, 15_000);
});
