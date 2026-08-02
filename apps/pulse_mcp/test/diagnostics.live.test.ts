/**
 * Soft live test — requires PulseService. Skips gracefully if unavailable.
 */
import { describe, expect, it } from "vitest";

import { getSharedDiagnosticsCache } from "../src/diagnostics/cache.js";
import {
  mapDiagnosticsSnapshot,
  mapServiceStatus,
} from "../src/diagnostics/mappers.js";
import { getSharedIpcSession } from "../src/ipc/session.js";

describe("diagnostics live (soft)", () => {
  it("GetDiagnosticsSnapshot via cache", async () => {
    const session = getSharedIpcSession();
    const cache = getSharedDiagnosticsCache(session);
    try {
      await session.ensureConnected();
    } catch {
      console.warn("SKIP diagnostics live — PulseService not reachable");
      return;
    }

    const snap = await cache.ensureSnapshot(true);
    expect(snap.serviceVersion || snap.buildVersion).toBeTruthy();
    expect(snap.protocolVersion).toBeGreaterThanOrEqual(1);

    const mapped = mapDiagnosticsSnapshot(snap);
    expect(typeof mapped.observedAt).toBe("string");
    expect(String(mapped.observedAt)).toMatch(/Z$/);

    const status = mapServiceStatus(snap);
    expect(
      (status.catalog as { available: boolean }).available,
    ).toBe(false);
  }, 15_000);
});
