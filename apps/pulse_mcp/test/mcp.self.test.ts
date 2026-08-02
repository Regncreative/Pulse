import { describe, expect, it } from "vitest";

import { INVENTORY_TOOLS_REGISTERED } from "../src/catalog/v1.js";
import { IpcSession } from "../src/ipc/session.js";
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
      session: new IpcSession(),
      activeSubscriptions: [],
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
      session: new IpcSession(),
      activeSubscriptions: [],
    });
    const body = JSON.parse(result.content[0]!.text) as {
      ok: boolean;
      data: {
        versions: Record<string, unknown>;
        namespaces: string[];
        capabilities: {
          tools: string[];
          resources: string[];
          subscriptions: string[];
          reportFormats: string[];
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
    expect(body.data.versions.mcpServer).toBe("0.7.0");
    expect(body.data.versions.pulseApp).toBe("0.2.1-beta");
    expect(body.data.versions.ipcProtocol).toBe(1);
    expect(body.data.namespaces).toContain("system");
    expect(body.data.namespaces).toContain("process");
    expect(body.data.namespaces).toContain("timeline");
    expect(body.data.namespaces).toContain("diagnostics");
    expect(body.data.namespaces).toContain("service");
    expect(body.data.namespaces).toContain("report");
    expect(body.data.capabilities.tools).toContain("mcp.self");
    expect(body.data.capabilities.tools).toContain("system.cpu");
    expect(body.data.capabilities.tools).toContain("process.list");
    expect(body.data.capabilities.tools).toContain("process.search");
    expect(body.data.capabilities.tools).toContain("process.details");
    expect(body.data.capabilities.tools).toContain("timeline.list");
    expect(body.data.capabilities.tools).toContain("timeline.search");
    expect(body.data.capabilities.tools).toContain("diagnostics.snapshot");
    expect(body.data.capabilities.tools).toContain("service.status");
    expect(body.data.capabilities.tools).toContain("report.export");
    expect(body.data.capabilities.tools).not.toContain("inventory.services");
    expect(body.data.capabilities.reportFormats).toEqual([
      "json",
      "html",
      "pdf",
      "markdown",
      "csv",
    ]);
    expect(body.data.capabilities.resources).toContain("pulse://system/cpu");
    expect(body.data.capabilities.resources).toContain("pulse://timeline/live");
    expect(body.data.capabilities.resources).toContain(
      "pulse://diagnostics/snapshot",
    );
    expect(body.data.capabilities.resources).toContain("pulse://mcp/status");
    expect(body.data.capabilities.subscriptions).toContain(
      "pulse://system/cpu",
    );
    expect(body.data.capabilities.subscriptions).toContain(
      "pulse://timeline/live",
    );
    expect(body.data.capabilities.subscriptions).toContain(
      "pulse://diagnostics/snapshot",
    );
    expect(body.data.capabilities.subscriptions).toContain(
      "pulse://mcp/status",
    );
    expect(body.data.capabilities.protocolFeatures).toContain(
      "resource_subscriptions",
    );
    expect(body.data.capabilities.inventoryToolsEnabled).toBe(false);
    expect(body.data.capabilities.inventoryToolsRegistered).toEqual([
      ...INVENTORY_TOOLS_REGISTERED,
    ]);
    expect(body.observedAt).toBeTruthy();
    expect(body.generatedAt).toBeTruthy();
    expect(typeof body.data.servicePipeConnected).toBe("boolean");
  });
});
