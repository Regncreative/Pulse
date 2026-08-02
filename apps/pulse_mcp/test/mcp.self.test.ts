import { describe, expect, it } from "vitest";

import { INVENTORY_TOOLS_REGISTERED } from "../src/catalog/v1.js";
import { MetricsRegistry } from "../src/metrics/metrics.js";
import { runMcpSelf } from "../src/tools/mcp/self.js";

describe("mcp.self", () => {
  it("returns POLICY_DISABLED when policy off", async () => {
    const metrics = new MetricsRegistry();
    const result = await runMcpSelf({
      metrics,
      policy: { enabled: false, path: "test-policy.json" },
      logPath: "test.log",
      transport: "stdio",
    });
    expect(result.isError).toBe(true);
    const text = result.content[0]!.text;
    const body = JSON.parse(text) as { ok: boolean; code: string };
    expect(body.ok).toBe(false);
    expect(body.code).toBe("POLICY_DISABLED");
  });

  it("returns capability discovery when enabled", async () => {
    const metrics = new MetricsRegistry();
    const result = await runMcpSelf({
      metrics,
      policy: { enabled: true, path: "test-policy.json" },
      logPath: "test.log",
      transport: "stdio",
    });
    const body = JSON.parse(result.content[0]!.text) as {
      ok: boolean;
      data: {
        versions: Record<string, unknown>;
        capabilities: {
          tools: string[];
          protocolFeatures: string[];
          inventoryToolsRegistered: string[];
          inventoryToolsEnabled: boolean;
        };
        servicePipeConnected: boolean;
      };
      observedAt: string;
      generatedAt: string;
    };
    expect(body.ok).toBe(true);
    expect(body.data.versions.mcpServer).toBe("0.1.0");
    expect(body.data.versions.ipcProtocol).toBe(1);
    expect(body.data.capabilities.tools).toContain("mcp.self");
    expect(body.data.capabilities.tools).not.toContain("inventory.services");
    expect(body.data.capabilities.protocolFeatures).toContain("stdio");
    expect(body.data.capabilities.inventoryToolsEnabled).toBe(false);
    expect(body.data.capabilities.inventoryToolsRegistered).toEqual([
      ...INVENTORY_TOOLS_REGISTERED,
    ]);
    expect(body.observedAt).toBeTruthy();
    expect(body.generatedAt).toBeTruthy();
    // May or may not be connected depending on host; field must exist.
    expect(typeof body.data.servicePipeConnected).toBe("boolean");
  });
});
