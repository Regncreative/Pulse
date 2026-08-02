/**
 * Pulse IPC protobuf codec (hello/ping + Health + process + Timeline).
 * Field numbers match shared/pulse_protocol/proto/pulse.proto.
 */

import { decodeDiagnosticsSnapshot } from "../diagnostics/decode.js";
import type { DiagnosticsSnapshot } from "../diagnostics/types.js";
import {
  decodeHealthSnapshot,
  decodeHealthUpdate,
  decodeProcessDetails,
} from "../health/decode.js";
import type {
  HealthProcessInventoryUpdate,
  HealthSample,
  HealthSnapshot,
  ProcessDetails,
} from "../health/types.js";
import {
  decodeTimelineEvent,
  decodeTimelineEventDetail,
  decodeTimelineSnapshot,
} from "../timeline/decode.js";
import type {
  TimelineEvent,
  TimelineEventDetail,
  TimelineSnapshot,
} from "../timeline/types.js";
import {
  Reader,
  writeBytesField,
  writeEmptyMessage,
  writeString,
  writeU64,
} from "./pb.js";

export interface ClientHello {
  type: "ClientHello";
  protocolVersion: number;
  clientName: string;
  clientVersion: string;
}

export interface ServerHello {
  type: "ServerHello";
  protocolVersion: number;
  serviceVersion: string;
}

export interface Ping {
  type: "Ping";
  nonce: number;
  unixMs: number;
}

export interface Pong {
  type: "Pong";
  nonce: number;
  unixMs: number;
  serviceVersion: string;
}

export interface GetHealthSnapshotMsg {
  type: "GetHealthSnapshot";
}

export interface HealthSnapshotMsg {
  type: "HealthSnapshot";
  snapshot: HealthSnapshot;
}

export interface HealthUpdateMsg {
  type: "HealthUpdate";
  sample: HealthSample;
  inventory: HealthProcessInventoryUpdate | null;
}

export interface StartHealthMonitoringMsg {
  type: "StartHealthMonitoring";
}

export interface StopHealthMonitoringMsg {
  type: "StopHealthMonitoring";
}

export interface GetProcessDetailsMsg {
  type: "GetProcessDetails";
  pid: number;
}

export interface ProcessDetailsMsg {
  type: "ProcessDetails";
  details: ProcessDetails;
}

export interface GetTimelineSnapshotMsg {
  type: "GetTimelineSnapshot";
  limit: number;
  channel: string;
}

export interface TimelineSnapshotMsg {
  type: "TimelineSnapshot";
  snapshot: TimelineSnapshot;
}

export interface LiveTimelineEventMsg {
  type: "LiveTimelineEvent";
  event: TimelineEvent;
}

export interface StartLiveMonitoringMsg {
  type: "StartLiveMonitoring";
  channel: string;
}

export interface StopLiveMonitoringMsg {
  type: "StopLiveMonitoring";
}

export interface GetTimelineEventDetailMsg {
  type: "GetTimelineEventDetail";
  channel: string;
  recordId: number;
}

export interface TimelineEventDetailMsg {
  type: "TimelineEventDetail";
  detail: TimelineEventDetail;
}

export interface GetDiagnosticsSnapshotMsg {
  type: "GetDiagnosticsSnapshot";
}

export interface DiagnosticsSnapshotMsg {
  type: "DiagnosticsSnapshot";
  snapshot: DiagnosticsSnapshot;
}

export interface ErrorResponseMsg {
  type: "ErrorResponse";
  code: number;
  message: string;
  technicalDetail: string;
  component: string;
}

export type Body =
  | ClientHello
  | ServerHello
  | Ping
  | Pong
  | GetHealthSnapshotMsg
  | HealthSnapshotMsg
  | HealthUpdateMsg
  | StartHealthMonitoringMsg
  | StopHealthMonitoringMsg
  | GetProcessDetailsMsg
  | ProcessDetailsMsg
  | GetTimelineSnapshotMsg
  | TimelineSnapshotMsg
  | LiveTimelineEventMsg
  | StartLiveMonitoringMsg
  | StopLiveMonitoringMsg
  | GetTimelineEventDetailMsg
  | TimelineEventDetailMsg
  | GetDiagnosticsSnapshotMsg
  | DiagnosticsSnapshotMsg
  | ErrorResponseMsg;

export interface Envelope {
  requestId: number;
  body: Body;
}

function encodeClientHello(m: ClientHello): Uint8Array {
  const out: number[] = [];
  writeU64(1, m.protocolVersion, out);
  writeString(2, m.clientName, out);
  writeString(3, m.clientVersion, out);
  return Uint8Array.from(out);
}

function encodePing(m: Ping): Uint8Array {
  const out: number[] = [];
  writeU64(1, m.nonce, out);
  writeU64(2, m.unixMs, out);
  return Uint8Array.from(out);
}

function encodeGetProcessDetails(m: GetProcessDetailsMsg): Uint8Array {
  const out: number[] = [];
  writeU64(1, m.pid, out);
  return Uint8Array.from(out);
}

function encodeGetTimelineSnapshot(m: GetTimelineSnapshotMsg): Uint8Array {
  const out: number[] = [];
  writeU64(1, m.limit, out);
  writeString(2, m.channel, out);
  return Uint8Array.from(out);
}

function encodeStartLiveMonitoring(m: StartLiveMonitoringMsg): Uint8Array {
  const out: number[] = [];
  writeString(1, m.channel, out);
  return Uint8Array.from(out);
}

function encodeGetTimelineEventDetail(
  m: GetTimelineEventDetailMsg,
): Uint8Array {
  const out: number[] = [];
  writeString(1, m.channel, out);
  writeU64(2, m.recordId, out);
  return Uint8Array.from(out);
}

export function encodeEnvelope(env: Envelope): Uint8Array {
  const out: number[] = [];
  writeU64(1, env.requestId, out);
  switch (env.body.type) {
    case "ClientHello":
      writeBytesField(10, encodeClientHello(env.body), out);
      break;
    case "Ping":
      writeBytesField(12, encodePing(env.body), out);
      break;
    case "GetTimelineSnapshot":
      writeBytesField(20, encodeGetTimelineSnapshot(env.body), out);
      break;
    case "StartLiveMonitoring":
      writeBytesField(23, encodeStartLiveMonitoring(env.body), out);
      break;
    case "StopLiveMonitoring":
      writeEmptyMessage(24, out);
      break;
    case "GetHealthSnapshot":
      writeEmptyMessage(25, out);
      break;
    case "StartHealthMonitoring":
      writeEmptyMessage(28, out);
      break;
    case "StopHealthMonitoring":
      writeEmptyMessage(29, out);
      break;
    case "GetDiagnosticsSnapshot":
      writeEmptyMessage(30, out);
      break;
    case "GetProcessDetails":
      writeBytesField(33, encodeGetProcessDetails(env.body), out);
      break;
    case "GetTimelineEventDetail":
      writeBytesField(35, encodeGetTimelineEventDetail(env.body), out);
      break;
    default:
      throw new Error(`encode not supported for ${env.body.type}`);
  }
  return Uint8Array.from(out);
}

function decodeServerHello(data: Uint8Array): ServerHello {
  const r = new Reader(data);
  const m: ServerHello = {
    type: "ServerHello",
    protocolVersion: 1,
    serviceVersion: "",
  };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 0) m.protocolVersion = r.readVarint();
    else if (field === 2 && wire === 2) m.serviceVersion = r.readString();
    else r.skip(wire);
  }
  return m;
}

function decodePong(data: Uint8Array): Pong {
  const r = new Reader(data);
  const m: Pong = { type: "Pong", nonce: 0, unixMs: 0, serviceVersion: "" };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 0) m.nonce = r.readVarint();
    else if (field === 2 && wire === 0) m.unixMs = Number(r.readVarintBig());
    else if (field === 3 && wire === 2) m.serviceVersion = r.readString();
    else r.skip(wire);
  }
  return m;
}

function decodeError(data: Uint8Array): ErrorResponseMsg {
  const r = new Reader(data);
  const m: ErrorResponseMsg = {
    type: "ErrorResponse",
    code: 0,
    message: "",
    technicalDetail: "",
    component: "",
  };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 0) m.code = r.readVarint();
    else if (field === 2 && wire === 2) m.message = r.readString();
    else if (field === 3 && wire === 2) m.technicalDetail = r.readString();
    else if (field === 4 && wire === 2) m.component = r.readString();
    else r.skip(wire);
  }
  return m;
}

export function decodeEnvelope(data: Uint8Array): Envelope {
  const r = new Reader(data);
  let requestId = 0;
  let body: Body | null = null;
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 0) {
      requestId = Number(r.readVarintBig());
    } else if (wire === 2) {
      const sub = r.readBytes();
      switch (field) {
        case 11:
          body = decodeServerHello(sub);
          break;
        case 13:
          body = decodePong(sub);
          break;
        case 21:
          body = {
            type: "TimelineSnapshot",
            snapshot: decodeTimelineSnapshot(sub),
          };
          break;
        case 22:
          body = {
            type: "LiveTimelineEvent",
            event: decodeTimelineEvent(sub),
          };
          break;
        case 26:
          body = {
            type: "HealthSnapshot",
            snapshot: decodeHealthSnapshot(sub),
          };
          break;
        case 27: {
          const update = decodeHealthUpdate(sub);
          body = {
            type: "HealthUpdate",
            sample: update.sample,
            inventory: update.inventory,
          };
          break;
        }
        case 31:
          body = {
            type: "DiagnosticsSnapshot",
            snapshot: decodeDiagnosticsSnapshot(sub),
          };
          break;
        case 34:
          body = {
            type: "ProcessDetails",
            details: decodeProcessDetails(sub),
          };
          break;
        case 36:
          body = {
            type: "TimelineEventDetail",
            detail: decodeTimelineEventDetail(sub),
          };
          break;
        case 99:
          body = decodeError(sub);
          break;
        default:
          break;
      }
    } else {
      r.skip(wire);
    }
  }
  if (!body) throw new Error("envelope missing body");
  return { requestId, body };
}
