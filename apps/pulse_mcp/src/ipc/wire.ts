/**
 * Pulse IPC protobuf codec (hello/ping + Health Engine messages for M2).
 * Field numbers match shared/pulse_protocol/proto/pulse.proto.
 */

import {
  decodeHealthSnapshot,
  decodeHealthUpdateSample,
} from "../health/decode.js";
import type { HealthSample, HealthSnapshot } from "../health/types.js";
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
}

export interface StartHealthMonitoringMsg {
  type: "StartHealthMonitoring";
}

export interface StopHealthMonitoringMsg {
  type: "StopHealthMonitoring";
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
    case "GetHealthSnapshot":
      writeEmptyMessage(25, out);
      break;
    case "StartHealthMonitoring":
      writeEmptyMessage(28, out);
      break;
    case "StopHealthMonitoring":
      writeEmptyMessage(29, out);
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
        case 26:
          body = {
            type: "HealthSnapshot",
            snapshot: decodeHealthSnapshot(sub),
          };
          break;
        case 27:
          body = {
            type: "HealthUpdate",
            sample: decodeHealthUpdateSample(sub),
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
