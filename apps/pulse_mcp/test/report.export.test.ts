import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { getSharedDiagnosticsCache } from "../src/diagnostics/cache.js";
import { getSharedHealthCache } from "../src/health/cache.js";
import { getSharedIpcSession } from "../src/ipc/session.js";
import { runReportExport } from "../src/report/export.js";
import { ReportExportError } from "../src/report/errors.js";
import { TempReportStore } from "../src/report/temp.js";
import { getSharedTimelineCache } from "../src/timeline/cache.js";

describe("report_export unit", () => {
  it("rejects invalid report type / format", async () => {
    const session = getSharedIpcSession();
    const deps = {
      session,
      health: getSharedHealthCache(session),
      timeline: getSharedTimelineCache(session),
      diagnostics: getSharedDiagnosticsCache(session),
    };
    await expect(
      runReportExport(deps, { reportType: "nope", format: "json" }),
    ).rejects.toMatchObject({ code: "INVALID_REPORT_TYPE" });
    await expect(
      runReportExport(deps, { reportType: "health", format: "xlsx" }),
    ).rejects.toMatchObject({ code: "INVALID_FORMAT" });
  });
});

describe("report_export live (soft)", () => {
  const tempRoot = path.join(os.tmpdir(), "Pulse", "mcp-reports-test");
  const store = new TempReportStore({ root: tempRoot, ttlMs: 100 });

  afterEach(async () => {
    await store.cleanupAll();
  });

  it("exports all formats and cleans temp reports", async () => {
    const session = getSharedIpcSession();
    try {
      await session.ensureConnected();
    } catch {
      console.warn("SKIP report_export live — PulseService not reachable");
      return;
    }

    const deps = {
      session,
      health: getSharedHealthCache(session),
      timeline: getSharedTimelineCache(session),
      diagnostics: getSharedDiagnosticsCache(session),
    };

    const formats = ["json", "csv", "html", "pdf", "markdown"] as const;
    const results = [];
    for (const format of formats) {
      const result = await runReportExport(
        deps,
        { reportType: "health", format },
        store,
      );
      expect(result.temporary).toBe(true);
      expect(result.bytes).toBeGreaterThan(0);
      expect(result.path).toBeTruthy();
      const st = await fs.stat(result.path);
      expect(st.size).toBe(result.bytes);
      if (format === "pdf") {
        const head = await fs.readFile(result.path);
        expect(head.subarray(0, 4).toString("utf8")).toBe("%PDF");
      }
      results.push(result);
    }

    // Concurrent exports
    const concurrent = await Promise.all(
      [1, 2, 3].map(() =>
        runReportExport(
          deps,
          { reportType: "timeline", format: "json", filters: { limit: 50 } },
          store,
        ),
      ),
    );
    expect(new Set(concurrent.map((r) => r.path)).size).toBe(3);

    // Large-ish timeline
    const large = await runReportExport(
      deps,
      { reportType: "timeline", format: "json", filters: { limit: 500 } },
      store,
    );
    expect(large.bytes).toBeGreaterThan(1000);

    // Force TTL cleanup
    await new Promise((r) => setTimeout(r, 120));
    const removed = await store.cleanupExpired();
    expect(removed).toBeGreaterThan(0);
    for (const r of results) {
      await expect(fs.access(r.path)).rejects.toBeTruthy();
    }

    // NOT_SUPPORTED diagnostics csv
    await expect(
      runReportExport(deps, { reportType: "diagnostics", format: "csv" }, store),
    ).rejects.toBeInstanceOf(ReportExportError);
  }, 60_000);
});
