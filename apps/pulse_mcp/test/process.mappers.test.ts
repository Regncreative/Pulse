import { describe, expect, it } from "vitest";

import { emptyProcessEntry } from "../src/health/types.js";
import {
  filterSortProcesses,
  mapProcessDetails,
  redactCommandLine,
} from "../src/process/mappers.js";
import { emptyProcessDetails } from "../src/health/types.js";

describe("process mappers", () => {
  it("redacts secret-like command line tokens", () => {
    const raw =
      'app.exe --token=abc123 --password secret password=plain api_key=xyz';
    const redacted = redactCommandLine(raw);
    expect(redacted).not.toContain("abc123");
    expect(redacted).not.toContain("plain");
    expect(redacted).toContain("***");
  });

  it("filters and sorts by cpu", () => {
    const a = emptyProcessEntry();
    a.pid = 1;
    a.name = "low.exe";
    a.hasCpuPercent = true;
    a.cpuPercent = 1;
    const b = emptyProcessEntry();
    b.pid = 2;
    b.name = "high.exe";
    b.hasCpuPercent = true;
    b.cpuPercent = 50;
    const result = filterSortProcesses([a, b], {
      cpuAbove: 5,
      sortBy: "cpu",
      sortDir: "desc",
      limit: 10,
    });
    expect(result.count).toBe(1);
    expect(result.processes[0]!.pid).toBe(2);
    expect(result.processes[0]!.id).toBe("2");
  });

  it("search query matches name", () => {
    const a = emptyProcessEntry();
    a.pid = 10;
    a.name = "chrome.exe";
    a.hasCreateTime = true;
    a.createTimeUnixMs = 1000;
    const b = emptyProcessEntry();
    b.pid = 11;
    b.name = "notepad.exe";
    const result = filterSortProcesses([a, b], { query: "chrome" });
    expect(result.count).toBe(1);
    expect(result.processes[0]!.id).toBe("10:1000");
  });

  it("maps details with redacted cmdline", () => {
    const d = emptyProcessDetails();
    d.pid = 42;
    d.name = "app.exe";
    d.hasCommandLine = true;
    d.commandLine = "app.exe --api-key=supersecret";
    d.hasCreateTime = true;
    d.createTimeUnixMs = 5_000;
    const mapped = mapProcessDetails(d);
    expect(mapped.commandLine).toContain("***");
    expect(String(mapped.commandLine)).not.toContain("supersecret");
    expect(mapped.id).toBe("42:5000");
  });
});
