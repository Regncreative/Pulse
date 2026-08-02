/**
 * Client-side Timeline filter/search — port of Flutter TimelineQuery.matches
 * (apps/pulse_app/lib/features/timeline/timeline_query.dart).
 */
import type { TimelineEvent } from "./types.js";

export type SeverityFilter =
  | "info"
  | "warning"
  | "error"
  | "critical"
  | "verbose"
  | "unknown";

export type ChannelFilter =
  | "system"
  | "application"
  | "security"
  | "other";

export interface TimelineSearchFilters {
  severity?: SeverityFilter[];
  category?: string;
  process?: string;
  provider?: string;
  eventId?: number;
  keyword?: string;
  from?: string;
  to?: string;
  channel?: ChannelFilter;
  computer?: string;
  limit?: number;
  offset?: number;
  includeRaw?: boolean;
}

function displayChannel(e: TimelineEvent): string {
  return e.channel || "System";
}

function displayTitle(e: TimelineEvent): string {
  if (e.title) return e.title;
  if (e.providerName) return e.providerName;
  return "Windows Event";
}

function displaySummary(e: TimelineEvent): string {
  if (e.summary) return e.summary;
  if (e.message) return e.message;
  return "No message available.";
}

function matchesSeverity(
  e: TimelineEvent,
  wanted: SeverityFilter[] | undefined,
): boolean {
  if (!wanted || wanted.length === 0) return true;
  const map: Record<number, SeverityFilter> = {
    0: "unknown",
    1: "info",
    2: "warning",
    3: "error",
    4: "critical",
    5: "verbose",
  };
  const name = map[e.severity] ?? "unknown";
  return wanted.includes(name);
}

function matchesChannel(
  e: TimelineEvent,
  channel: ChannelFilter | undefined,
): boolean {
  if (!channel) return true;
  const ch = displayChannel(e).toLowerCase();
  switch (channel) {
    case "system":
      return ch === "system";
    case "application":
      return ch === "application";
    case "security":
      return ch === "security";
    case "other":
      return ch !== "system" && ch !== "application" && ch !== "security";
    default:
      return true;
  }
}

function matchesCategory(e: TimelineEvent, category: string | undefined): boolean {
  if (!category || !category.trim()) return true;
  const c = e.category.toLowerCase();
  const want = category.trim().toLowerCase();
  if (want === "device") return c === "device" || c === "driver";
  return c === want;
}

function matchesRange(
  e: TimelineEvent,
  fromIso: string | undefined,
  toIso: string | undefined,
): boolean {
  if (!fromIso && !toIso) return true;
  if (e.timestampUnixMs <= 0) return false;
  if (fromIso) {
    const from = Date.parse(fromIso);
    if (!Number.isNaN(from) && e.timestampUnixMs < from) return false;
  }
  if (toIso) {
    const to = Date.parse(toIso);
    if (!Number.isNaN(to) && e.timestampUnixMs > to) return false;
  }
  return true;
}

function matchesProvider(e: TimelineEvent, provider: string | undefined): boolean {
  const needle = provider?.trim().toLowerCase() ?? "";
  if (!needle) return true;
  return e.providerName.toLowerCase().includes(needle);
}

function matchesEventId(e: TimelineEvent, eventId: number | undefined): boolean {
  if (eventId === undefined || eventId === null) return true;
  return e.winEventId === eventId;
}

function matchesProcess(e: TimelineEvent, process: string | undefined): boolean {
  const needle = process?.trim().toLowerCase() ?? "";
  if (!needle) return true;
  if (e.processName.toLowerCase().includes(needle)) return true;
  if (e.hasProcessId && String(e.processId).includes(needle)) return true;
  return false;
}

function matchesComputer(e: TimelineEvent, computer: string | undefined): boolean {
  const needle = computer?.trim().toLowerCase() ?? "";
  if (!needle) return true;
  return e.computerName.toLowerCase().includes(needle);
}

function matchesKeyword(e: TimelineEvent, keyword: string | undefined): boolean {
  const q = keyword?.trim().toLowerCase() ?? "";
  if (!q) return true;
  const haystack = [
    displayTitle(e),
    displaySummary(e),
    e.message,
    e.technicalSummary,
    e.providerName,
    displayChannel(e),
    e.category,
    e.computerName,
    e.processName,
    e.userSid,
    e.activityId,
    e.relatedActivityId,
    e.levelName,
    e.rawXml,
    String(e.winEventId),
    String(e.recordId),
    e.hasProcessId ? String(e.processId) : "",
    e.hasKeywords ? e.keywords.toString(16) : "",
    e.hasTask ? String(e.task) : "",
    e.hasOpcode ? String(e.opcode) : "",
  ]
    .join(" ")
    .toLowerCase();
  return haystack.includes(q);
}

export function matchesTimelineEvent(
  e: TimelineEvent,
  filters: TimelineSearchFilters,
): boolean {
  if (!matchesSeverity(e, filters.severity)) return false;
  if (!matchesChannel(e, filters.channel)) return false;
  if (!matchesCategory(e, filters.category)) return false;
  if (!matchesRange(e, filters.from, filters.to)) return false;
  if (!matchesProvider(e, filters.provider)) return false;
  if (!matchesEventId(e, filters.eventId)) return false;
  if (!matchesProcess(e, filters.process)) return false;
  if (!matchesComputer(e, filters.computer)) return false;
  return matchesKeyword(e, filters.keyword);
}

export function filterTimelineEvents(
  events: TimelineEvent[],
  filters: TimelineSearchFilters,
): TimelineEvent[] {
  return events.filter((e) => matchesTimelineEvent(e, filters));
}
