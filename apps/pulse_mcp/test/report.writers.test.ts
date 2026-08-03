import { describe, expect, it } from "vitest";

import { ReportExportError } from "../src/report/errors.js";
import type { ReportModel } from "../src/report/types.js";
import {
  buildCsv,
  buildHtml,
  buildJson,
  buildMarkdown,
  buildPdf,
} from "../src/report/writers.js";

function sampleModel(template: ReportModel["template"] = "health"): ReportModel {
  return {
    pulse_export: "pulse-health",
    template,
    version: 1,
    exported_at: "2026-08-02T12:00:00.000Z",
    pulse_version: "1.0.0",
    mcp_version: "1.0.0",
    system_identity: { windows: "Windows 10 Pro", cpu: "Test CPU" },
    sections: {
      health: { cpu: { usagePercent: 12.5 } },
      timeline: {
        count: 1,
        events: [
          {
            observedAt: "2026-08-02T12:00:00.000Z",
            severity: "info",
            title: "Test",
            channel: "System",
            provider: "Test",
            eventId: 1,
            processName: null,
          },
        ],
      },
    },
  };
}

describe("report writers", () => {
  it("builds json without report body streaming markers", () => {
    const buf = buildJson(sampleModel());
    const text = buf.toString("utf8");
    expect(text).toContain('"template": "health"');
    expect(text).toContain("Test CPU");
  });

  it("builds csv / html / markdown", () => {
    const model = sampleModel();
    expect(buildCsv("health", model).toString("utf8")).toContain("usagePercent");
    expect(buildHtml(model).toString("utf8")).toContain("<!DOCTYPE html>");
    expect(buildMarkdown(model).toString("utf8")).toContain("# Pulse");
  });

  it("rejects diagnostics csv", () => {
    expect(() => buildCsv("diagnostics", sampleModel("diagnostics"))).toThrow(
      ReportExportError,
    );
  });

  it("builds pdf bytes with PDF header", async () => {
    const buf = await buildPdf(sampleModel());
    expect(buf.subarray(0, 4).toString("utf8")).toBe("%PDF");
    expect(buf.length).toBeGreaterThan(100);
  });
});
