import { describe, expect, it } from "vitest";

import { emptyTimelineEvent } from "../src/timeline/types.js";
import { filterTimelineEvents, matchesTimelineEvent } from "../src/timeline/query.js";
import { mapTimelineEvent } from "../src/timeline/mappers.js";

describe("timeline query (Flutter parity)", () => {
  it("filters by severity error/critical", () => {
    const err = emptyTimelineEvent();
    err.severity = 3;
    err.title = "Crash";
    const info = emptyTimelineEvent();
    info.severity = 1;
    info.title = "Info";
    const matched = filterTimelineEvents([err, info], {
      severity: ["error", "critical"],
    });
    expect(matched).toHaveLength(1);
    expect(matched[0]!.title).toBe("Crash");
  });

  it("filters channel security vs system", () => {
    const sec = emptyTimelineEvent();
    sec.channel = "Security";
    const sys = emptyTimelineEvent();
    sys.channel = "System";
    expect(matchesTimelineEvent(sec, { channel: "security" })).toBe(true);
    expect(matchesTimelineEvent(sys, { channel: "security" })).toBe(false);
  });

  it("keyword search covers provider and message", () => {
    const e = emptyTimelineEvent();
    e.providerName = "Microsoft-Windows-Kernel-Power";
    e.message = "The system is entering sleep.";
    expect(matchesTimelineEvent(e, { keyword: "kernel-power" })).toBe(true);
    expect(matchesTimelineEvent(e, { keyword: "sleep" })).toBe(true);
    expect(matchesTimelineEvent(e, { keyword: "nomatch" })).toBe(false);
  });

  it("maps event without rawXml by default", () => {
    const e = emptyTimelineEvent();
    e.eventId = "abc";
    e.timestampIso = "2026-08-02T00:00:00.000Z";
    e.severity = 2;
    e.title = "Warn";
    e.summary = "Something";
    e.rawXml = "<Event/>";
    const mapped = mapTimelineEvent(e);
    expect(mapped.rawXml).toBeUndefined();
    expect(mapped.severity).toBe("warning");
    const withRaw = mapTimelineEvent(e, { includeRaw: true });
    expect(withRaw.rawXml).toBe("<Event/>");
  });
});
