import type { TimelineEvent } from "./types.js";
import { severityName } from "./types.js";

export function mapTimelineEvent(
  e: TimelineEvent,
  opts: { includeRaw?: boolean } = {},
): Record<string, unknown> {
  const includeRaw = opts.includeRaw === true;
  const observedAt =
    e.timestampIso ||
    (e.timestampUnixMs > 0
      ? new Date(e.timestampUnixMs).toISOString()
      : new Date().toISOString());

  const row: Record<string, unknown> = {
    id: e.eventId || `${e.channel}:${e.recordId}`,
    observedAt,
    severity: severityName(e.severity),
    title: e.title || e.providerName || "Windows Event",
    summary: e.summary || e.message || "No message available.",
    technical: e.technicalSummary || null,
    channel: e.channel || null,
    provider: e.providerName || null,
    eventId: e.winEventId || null,
    recordId: e.recordId || null,
    processName: e.processName || null,
    pid: e.hasProcessId ? e.processId : null,
    category: e.category || null,
    computer: e.computerName || null,
  };

  if (includeRaw) {
    row.rawXml = e.rawXml || null;
    if (!e.rawXml) {
      row.unavailable = { rawXml: "Not available for this event" };
    }
  }

  return row;
}

export function parseAccessibleChannels(channelLabel: string): string[] {
  if (!channelLabel.trim()) return [];
  return channelLabel
    .split(",")
    .map((c) => c.trim())
    .filter(Boolean);
}

export function securityChannelAvailable(channelLabel: string): boolean {
  return parseAccessibleChannels(channelLabel).some(
    (c) => c.toLowerCase() === "security",
  );
}
