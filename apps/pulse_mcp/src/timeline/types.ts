/** Decoded Timeline Engine types (MCP M4). */

export type TimelineSeverityName =
  | "unknown"
  | "info"
  | "warning"
  | "error"
  | "critical"
  | "verbose";

export interface TimelineEvent {
  eventId: string;
  timestampUnixMs: number;
  timestampIso: string;
  severity: number;
  channel: string;
  providerName: string;
  winEventId: number;
  recordId: number;
  computerName: string;
  summary: string;
  technicalSummary: string;
  message: string;
  title: string;
  recommendation: string;
  actionRequired: boolean;
  importance: number;
  category: string;
  task: number;
  hasTask: boolean;
  opcode: number;
  hasOpcode: boolean;
  keywords: number;
  hasKeywords: boolean;
  processId: number;
  hasProcessId: boolean;
  processName: string;
  threadId: number;
  hasThreadId: boolean;
  userSid: string;
  activityId: string;
  relatedActivityId: string;
  levelName: string;
  rawXml: string;
}

export interface TimelineSnapshot {
  events: TimelineEvent[];
  channel: string;
  requestedLimit: number;
  collectedUnixMs: number;
}

export interface TimelineEventDetail {
  found: boolean;
  event: TimelineEvent | null;
}

export function emptyTimelineEvent(): TimelineEvent {
  return {
    eventId: "",
    timestampUnixMs: 0,
    timestampIso: "",
    severity: 0,
    channel: "",
    providerName: "",
    winEventId: 0,
    recordId: 0,
    computerName: "",
    summary: "",
    technicalSummary: "",
    message: "",
    title: "",
    recommendation: "",
    actionRequired: false,
    importance: 0,
    category: "",
    task: 0,
    hasTask: false,
    opcode: 0,
    hasOpcode: false,
    keywords: 0,
    hasKeywords: false,
    processId: 0,
    hasProcessId: false,
    processName: "",
    threadId: 0,
    hasThreadId: false,
    userSid: "",
    activityId: "",
    relatedActivityId: "",
    levelName: "",
    rawXml: "",
  };
}

export function severityName(sev: number): TimelineSeverityName {
  switch (sev) {
    case 1:
      return "info";
    case 2:
      return "warning";
    case 3:
      return "error";
    case 4:
      return "critical";
    case 5:
      return "verbose";
    default:
      return "unknown";
  }
}
