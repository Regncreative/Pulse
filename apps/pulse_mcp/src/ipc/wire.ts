/** Minimal Pulse IPC protobuf codec for hello/ping (matches pulse_wire). */

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

export type Body = ClientHello | ServerHello | Ping | Pong;

export interface Envelope {
  requestId: number;
  body: Body;
}

function writeVarint(value: number, out: number[]): void {
  let v = value >>> 0;
  while (v >= 0x80) {
    out.push((v & 0x7f) | 0x80);
    v >>>= 7;
  }
  out.push(v & 0x7f);
}

function writeTag(field: number, wire: number, out: number[]): void {
  writeVarint((field << 3) | wire, out);
}

function writeString(field: number, s: string, out: number[]): void {
  const bytes = Buffer.from(s, "utf8");
  writeTag(field, 2, out);
  writeVarint(bytes.length, out);
  for (const b of bytes) out.push(b);
}

function writeU64(field: number, v: number, out: number[]): void {
  writeTag(field, 0, out);
  writeVarint(v, out);
}

function writeBytesField(field: number, bytes: Uint8Array, out: number[]): void {
  writeTag(field, 2, out);
  writeVarint(bytes.length, out);
  for (const b of bytes) out.push(b);
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
    default:
      throw new Error(`encode not supported for ${env.body.type}`);
  }
  return Uint8Array.from(out);
}

class Reader {
  offset = 0;
  constructor(readonly data: Uint8Array) {}

  get hasMore(): boolean {
    return this.offset < this.data.length;
  }

  readVarint(): number {
    let result = 0;
    let shift = 0;
    while (this.offset < this.data.length) {
      const b = this.data[this.offset++]!;
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) === 0) return result >>> 0;
      shift += 7;
    }
    throw new Error("truncated varint");
  }

  readString(): string {
    const len = this.readVarint();
    const bytes = this.data.subarray(this.offset, this.offset + len);
    this.offset += len;
    return Buffer.from(bytes).toString("utf8");
  }

  skip(wire: number): void {
    switch (wire) {
      case 0:
        this.readVarint();
        break;
      case 1:
        this.offset += 8;
        break;
      case 2: {
        const len = this.readVarint();
        this.offset += len;
        break;
      }
      case 5:
        this.offset += 4;
        break;
      default:
        throw new Error(`unknown wire ${wire}`);
    }
  }
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
    else if (field === 2 && wire === 0) m.unixMs = r.readVarint();
    else if (field === 3 && wire === 2) m.serviceVersion = r.readString();
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
      requestId = r.readVarint();
    } else if (wire === 2 && (field === 11 || field === 13)) {
      const len = r.readVarint();
      const sub = r.data.subarray(r.offset, r.offset + len);
      r.offset += len;
      if (field === 11) body = decodeServerHello(sub);
      else body = decodePong(sub);
    } else {
      r.skip(wire);
    }
  }
  if (!body) throw new Error("envelope missing body");
  return { requestId, body };
}
