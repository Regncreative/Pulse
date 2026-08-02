/** Shared protobuf wire helpers for Pulse IPC. */

export function writeVarint(value: number | bigint, out: number[]): void {
  let v =
    typeof value === "bigint"
      ? value < 0n
        ? 0n
        : value
      : BigInt(value >>> 0);
  // Support large uint64 for timestamps / bytes.
  if (typeof value === "number" && value > 0xffffffff) {
    v = BigInt(Math.floor(value));
  }
  while (v >= 0x80n) {
    out.push(Number(v & 0x7fn) | 0x80);
    v >>= 7n;
  }
  out.push(Number(v));
}

export function writeTag(field: number, wire: number, out: number[]): void {
  writeVarint((field << 3) | wire, out);
}

export function writeString(field: number, s: string, out: number[]): void {
  const bytes = Buffer.from(s, "utf8");
  writeTag(field, 2, out);
  writeVarint(bytes.length, out);
  for (const b of bytes) out.push(b);
}

export function writeU64(field: number, v: number, out: number[]): void {
  writeTag(field, 0, out);
  writeVarint(v, out);
}

export function writeBytesField(
  field: number,
  bytes: Uint8Array,
  out: number[],
): void {
  writeTag(field, 2, out);
  writeVarint(bytes.length, out);
  for (const b of bytes) out.push(b);
}

export function writeEmptyMessage(field: number, out: number[]): void {
  writeBytesField(field, new Uint8Array(0), out);
}

export class Reader {
  offset = 0;
  constructor(readonly data: Uint8Array) {}

  get hasMore(): boolean {
    return this.offset < this.data.length;
  }

  readVarint(): number {
    let result = 0n;
    let shift = 0n;
    while (this.offset < this.data.length) {
      const b = BigInt(this.data[this.offset++]!);
      result |= (b & 0x7fn) << shift;
      if ((b & 0x80n) === 0n) {
        // Safe for JS number for our field sizes; clamp if huge.
        if (result > BigInt(Number.MAX_SAFE_INTEGER)) {
          return Number(result & 0xffffffffn);
        }
        return Number(result);
      }
      shift += 7n;
      if (shift > 63n) throw new Error("varint too long");
    }
    throw new Error("truncated varint");
  }

  readVarintBig(): bigint {
    let result = 0n;
    let shift = 0n;
    while (this.offset < this.data.length) {
      const b = BigInt(this.data[this.offset++]!);
      result |= (b & 0x7fn) << shift;
      if ((b & 0x80n) === 0n) return result;
      shift += 7n;
      if (shift > 63n) throw new Error("varint too long");
    }
    throw new Error("truncated varint");
  }

  readString(): string {
    const len = this.readVarint();
    const bytes = this.data.subarray(this.offset, this.offset + len);
    this.offset += len;
    return Buffer.from(bytes).toString("utf8");
  }

  readBytes(): Uint8Array {
    const len = this.readVarint();
    const bytes = this.data.subarray(this.offset, this.offset + len);
    this.offset += len;
    return bytes;
  }

  readDouble(): number {
    const view = new DataView(
      this.data.buffer,
      this.data.byteOffset + this.offset,
      8,
    );
    const v = view.getFloat64(0, true);
    this.offset += 8;
    return v;
  }

  skip(wire: number): void {
    switch (wire) {
      case 0:
        this.readVarintBig();
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
