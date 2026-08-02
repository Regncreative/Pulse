import { describe, expect, it } from "vitest";

import {
  mapCpu,
  mapHealth,
  mapMemory,
  mapStorage,
} from "../src/health/mappers.js";
import { emptySample, emptyStaticInfo } from "../src/health/types.js";

describe("health mappers", () => {
  it("maps CPU with unavailable temperature", () => {
    const sample = emptySample();
    sample.unixMs = Date.parse("2026-08-02T10:00:00.000Z");
    sample.hasCpuPercent = true;
    sample.cpuPercent = 12.5;
    sample.hasCpuCurrentMhz = true;
    sample.cpuCurrentMhz = 4200;
    const info = emptyStaticInfo();
    info.cpuLogicalProcessors = 16;
    info.cpuCores = 8;
    const cpu = mapCpu(sample, info);
    expect(cpu.usagePercent).toBe(12.5);
    expect(cpu.logicalProcessors).toBe(16);
    expect(cpu.temperatureCelsius).toBeNull();
    expect(cpu.unavailable?.temperatureCelsius).toBe("Not supported");
    expect(cpu.observedAt).toBe("2026-08-02T10:00:00.000Z");
  });

  it("maps memory usage percent", () => {
    const sample = emptySample();
    sample.unixMs = 1;
    sample.memoryUsedBytes = 50;
    sample.memoryTotalBytes = 100;
    sample.memoryAvailableBytes = 50;
    const mem = mapMemory(sample, emptyStaticInfo());
    expect(mem.usagePercent).toBe(50);
    expect(mem.totalBytes).toBe(100);
  });

  it("maps volumes without inventing capacity", () => {
    const sample = emptySample();
    sample.unixMs = 1;
    sample.volumes.push({
      id: "Z:",
      mountPoint: "Z:\\",
      label: "",
      fileSystem: "NTFS",
      kind: 3,
      usedBytes: 0,
      totalBytes: 0,
      hasCapacity: false,
      includedInSummary: false,
    });
    const storage = mapStorage(sample, emptyStaticInfo());
    expect(storage.volumes[0]!.usedBytes).toBeNull();
    expect(storage.volumes[0]!.hasCapacity).toBe(false);
  });

  it("sections filter system.health", () => {
    const sample = emptySample();
    sample.unixMs = 1;
    sample.hasCpuPercent = true;
    sample.cpuPercent = 1;
    const data = mapHealth(
      { info: emptyStaticInfo(), sample },
      ["cpu"],
    ) as Record<string, unknown>;
    expect(data.cpu).toBeTruthy();
    expect(data.memory).toBeUndefined();
    expect(data.static).toBeUndefined();
  });
});
