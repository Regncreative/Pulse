import { describe, expect, it } from "vitest";

import {
  mapDiagnosticsSnapshot,
  mapServiceStatus,
} from "../src/diagnostics/mappers.js";
import { emptyDiagnosticsSnapshot } from "../src/diagnostics/types.js";

describe("diagnostics mappers", () => {
  it("maps snapshot with ISO-8601 UTC observedAt and stage labels", () => {
    const snap = emptyDiagnosticsSnapshot();
    snap.serviceVersion = "0.2.0-beta";
    snap.serviceStartUnixMs = Date.parse("2026-08-02T10:00:00.000Z");
    snap.serviceUptimeMs = 60_000;
    snap.stageEventLog = 0;
    snap.stageCollector = 1;
    snap.stageIntelligence = 2;
    snap.scmState = "Running";
    snap.ipcListening = true;

    const mapped = mapDiagnosticsSnapshot(snap);
    expect(mapped.observedAt).toBe("2026-08-02T10:01:00.000Z");
    expect((mapped.pipeline as { collector: { state: string } }).collector.state).toBe(
      "warning",
    );
    expect(
      (mapped.pipeline as { intelligence: { state: string } }).intelligence.state,
    ).toBe("error");
    expect((mapped.service as { version: string }).version).toBe("0.2.0-beta");
    expect((mapped.service as { ipcListening: boolean }).ipcListening).toBe(
      true,
    );
  });

  it("service.status exposes PulseService only; catalog unavailable", () => {
    const snap = emptyDiagnosticsSnapshot();
    snap.scmState = "Running";
    snap.scmStartupType = "Automatic";
    snap.executablePath = "C:\\Pulse\\PulseService.exe";
    snap.serviceVersion = "0.2.0-beta";
    snap.servicePid = 4242;

    const status = mapServiceStatus(snap);
    const pulse = status.pulseService as Record<string, unknown>;
    expect(pulse.installed).toBe(true);
    expect(pulse.running).toBe(true);
    expect(pulse.startType).toBe("Automatic");
    expect(pulse.path).toContain("PulseService");
    expect(pulse.account).toBeNull();
    expect(pulse.pid).toBe(4242);

    const catalog = status.catalog as { available: boolean; reason: string };
    expect(catalog.available).toBe(false);
    expect(catalog.reason.toLowerCase()).toContain("inventory");
  });

  it("service.status marks not-installed when SCM empty and no path", () => {
    const snap = emptyDiagnosticsSnapshot();
    const status = mapServiceStatus(snap);
    const pulse = status.pulseService as Record<string, unknown>;
    expect(pulse.installed).toBe(false);
    expect(pulse.running).toBe(false);
  });
});
