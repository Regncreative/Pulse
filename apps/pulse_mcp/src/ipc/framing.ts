const MAGIC = Buffer.from([0x50, 0x55, 0x4c, 0x53]); // PULS
const MAX_PAYLOAD = 2 * 1024 * 1024;

export function encodeFrame(payload: Uint8Array): Buffer {
  if (payload.length > MAX_PAYLOAD) {
    throw new Error("payload exceeds 2 MB");
  }
  const out = Buffer.allocUnsafe(8 + payload.length);
  MAGIC.copy(out, 0);
  out.writeUInt32LE(payload.length, 4);
  Buffer.from(payload).copy(out, 8);
  return out;
}

export interface FrameDecode {
  payload: Buffer;
  consumed: number;
}

export function tryDecodeFrame(data: Buffer): FrameDecode | null {
  if (data.length < 8) return null;
  if (
    data[0] !== 0x50 ||
    data[1] !== 0x55 ||
    data[2] !== 0x4c ||
    data[3] !== 0x53
  ) {
    throw new Error("invalid frame magic");
  }
  const plen = data.readUInt32LE(4);
  if (plen > MAX_PAYLOAD) {
    throw new Error("frame exceeds 2 MB");
  }
  if (data.length < 8 + plen) return null;
  return {
    payload: data.subarray(8, 8 + plen),
    consumed: 8 + plen,
  };
}
