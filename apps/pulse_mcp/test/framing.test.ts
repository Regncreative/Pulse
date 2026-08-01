import { describe, expect, it } from "vitest";

import { encodeFrame, tryDecodeFrame } from "../src/ipc/framing.js";

describe("IPC framing", () => {
  it("roundtrips payload", () => {
    const payload = Buffer.from([1, 2, 3, 4, 5]);
    const frame = encodeFrame(payload);
    expect(frame.subarray(0, 4).toString("ascii")).toBe("PULS");
    const decoded = tryDecodeFrame(frame);
    expect(decoded).not.toBeNull();
    expect(decoded!.payload.equals(payload)).toBe(true);
    expect(decoded!.consumed).toBe(frame.length);
  });

  it("waits for full frame", () => {
    const frame = encodeFrame(Buffer.from("hello"));
    expect(tryDecodeFrame(frame.subarray(0, 4))).toBeNull();
  });
});
