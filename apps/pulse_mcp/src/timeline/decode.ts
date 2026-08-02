import { Reader } from "../ipc/pb.js";
import {
  emptyTimelineEvent,
  type TimelineEvent,
  type TimelineEventDetail,
  type TimelineSnapshot,
} from "./types.js";

export function decodeTimelineEvent(data: Uint8Array): TimelineEvent {
  const r = new Reader(data);
  const m = emptyTimelineEvent();
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    const setBool = () => r.readVarint() !== 0;
    const setU64 = () => Number(r.readVarintBig());
    if (field === 1 && wire === 2) m.eventId = r.readString();
    else if (field === 2 && wire === 0) m.timestampUnixMs = setU64();
    else if (field === 3 && wire === 2) m.timestampIso = r.readString();
    else if (field === 4 && wire === 0) m.severity = r.readVarint();
    else if (field === 5 && wire === 2) m.channel = r.readString();
    else if (field === 6 && wire === 2) m.providerName = r.readString();
    else if (field === 7 && wire === 0) m.winEventId = r.readVarint();
    else if (field === 8 && wire === 0) m.recordId = setU64();
    else if (field === 9 && wire === 2) m.computerName = r.readString();
    else if (field === 10 && wire === 2) m.summary = r.readString();
    else if (field === 11 && wire === 2) m.technicalSummary = r.readString();
    else if (field === 12 && wire === 2) m.message = r.readString();
    else if (field === 13 && wire === 2) m.title = r.readString();
    else if (field === 14 && wire === 2) m.recommendation = r.readString();
    else if (field === 15 && wire === 0) m.actionRequired = setBool();
    else if (field === 16 && wire === 0) m.importance = r.readVarint();
    else if (field === 17 && wire === 2) m.category = r.readString();
    else if (field === 18 && wire === 0) m.task = r.readVarint();
    else if (field === 19 && wire === 0) m.hasTask = setBool();
    else if (field === 20 && wire === 0) m.opcode = r.readVarint();
    else if (field === 21 && wire === 0) m.hasOpcode = setBool();
    else if (field === 22 && wire === 0) m.keywords = setU64();
    else if (field === 23 && wire === 0) m.hasKeywords = setBool();
    else if (field === 24 && wire === 0) m.processId = r.readVarint();
    else if (field === 25 && wire === 0) m.hasProcessId = setBool();
    else if (field === 26 && wire === 2) m.processName = r.readString();
    else if (field === 27 && wire === 0) m.threadId = r.readVarint();
    else if (field === 28 && wire === 0) m.hasThreadId = setBool();
    else if (field === 29 && wire === 2) m.userSid = r.readString();
    else if (field === 30 && wire === 2) m.activityId = r.readString();
    else if (field === 31 && wire === 2) m.relatedActivityId = r.readString();
    else if (field === 32 && wire === 2) m.levelName = r.readString();
    else if (field === 33 && wire === 2) m.rawXml = r.readString();
    else r.skip(wire);
  }
  return m;
}

export function decodeTimelineSnapshot(data: Uint8Array): TimelineSnapshot {
  const r = new Reader(data);
  const m: TimelineSnapshot = {
    events: [],
    channel: "",
    requestedLimit: 0,
    collectedUnixMs: 0,
  };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 2)
      m.events.push(decodeTimelineEvent(r.readBytes()));
    else if (field === 2 && wire === 2) m.channel = r.readString();
    else if (field === 3 && wire === 0) m.requestedLimit = r.readVarint();
    else if (field === 4 && wire === 0)
      m.collectedUnixMs = Number(r.readVarintBig());
    else r.skip(wire);
  }
  return m;
}

export function decodeTimelineEventDetail(
  data: Uint8Array,
): TimelineEventDetail {
  const r = new Reader(data);
  const m: TimelineEventDetail = { found: false, event: null };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 0) m.found = r.readVarint() !== 0;
    else if (field === 2 && wire === 2)
      m.event = decodeTimelineEvent(r.readBytes());
    else r.skip(wire);
  }
  return m;
}
