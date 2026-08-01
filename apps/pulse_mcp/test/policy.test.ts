import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { loadPolicy, writePolicy } from "../src/policy/policy.js";

describe("policy", () => {
  const prev = process.env.PULSE_MCP_ENABLED;
  const prevPath = process.env.PULSE_MCP_POLICY_PATH;

  afterEach(() => {
    if (prev === undefined) delete process.env.PULSE_MCP_ENABLED;
    else process.env.PULSE_MCP_ENABLED = prev;
    if (prevPath === undefined) delete process.env.PULSE_MCP_POLICY_PATH;
    else process.env.PULSE_MCP_POLICY_PATH = prevPath;
  });

  it("defaults to disabled when file missing", () => {
    delete process.env.PULSE_MCP_ENABLED;
    const p = path.join(os.tmpdir(), `pulse-mcp-policy-${Date.now()}.json`);
    if (fs.existsSync(p)) fs.unlinkSync(p);
    const policy = loadPolicy(p);
    expect(policy.enabled).toBe(false);
  });

  it("reads enabled from file", () => {
    delete process.env.PULSE_MCP_ENABLED;
    const p = path.join(os.tmpdir(), `pulse-mcp-policy-${Date.now()}.json`);
    writePolicy(true, p);
    expect(loadPolicy(p).enabled).toBe(true);
    fs.unlinkSync(p);
  });

  it("env overrides file", () => {
    const p = path.join(os.tmpdir(), `pulse-mcp-policy-${Date.now()}.json`);
    writePolicy(false, p);
    process.env.PULSE_MCP_ENABLED = "true";
    expect(loadPolicy(p).enabled).toBe(true);
    fs.unlinkSync(p);
  });
});
