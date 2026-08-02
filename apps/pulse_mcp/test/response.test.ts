import { describe, expect, it } from "vitest";

import { failure, success } from "../src/response/envelope.js";

describe("response envelope", () => {
  it("success includes observedAt and generatedAt", () => {
    const body = success(
      "mcp_self",
      { hello: true },
      {
        mcpVersion: "0.1.0",
        ipcProtocolVersion: 1,
        serviceVersion: "0.2.0-beta",
        observedAt: "2026-01-01T00:00:00.000Z",
      },
    );
    expect(body.ok).toBe(true);
    expect(body.observedAt).toBe("2026-01-01T00:00:00.000Z");
    expect(body.generatedAt).toMatch(/^\d{4}-/);
    expect(body.pulse.mcpVersion).toBe("0.1.0");
  });

  it("failure is structured with code", () => {
    const body = failure("mcp_self", "POLICY_DISABLED", "off", {
      policyPath: "x",
    });
    expect(body.ok).toBe(false);
    expect(body.code).toBe("POLICY_DISABLED");
    expect(body.message).toBe("off");
    expect(body.details.policyPath).toBe("x");
  });
});
