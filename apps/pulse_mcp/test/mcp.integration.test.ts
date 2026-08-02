import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { describe, expect, it } from "vitest";

import { getSharedHealthCache } from "../src/health/cache.js";
import { getSharedIpcSession } from "../src/ipc/session.js";
import { PulseMcpLogger } from "../src/logging/logger.js";
import { MetricsRegistry } from "../src/metrics/metrics.js";
import { createPulseMcpServer } from "../src/server/createServer.js";
import { getSharedTimelineCache } from "../src/timeline/cache.js";

describe("MCP integration (in-memory)", () => {
  it("lists M2–M4 tools and mcp.self", async () => {
    const session = getSharedIpcSession();
    const health = getSharedHealthCache(session);
    const timeline = getSharedTimelineCache(session);
    const mcp = createPulseMcpServer({
      metrics: new MetricsRegistry(),
      policy: { enabled: true, path: "test-policy.json" },
      logger: new PulseMcpLogger(),
      session,
      health,
      timeline,
    });
    const [clientTransport, serverTransport] =
      InMemoryTransport.createLinkedPair();
    const client = new Client({ name: "test", version: "0.0.1" });
    await Promise.all([
      mcp.connect(serverTransport),
      client.connect(clientTransport),
    ]);

    const tools = await client.listTools();
    const names = tools.tools.map((t) => t.name).sort();
    expect(names).toContain("mcp.self");
    expect(names).toContain("system.cpu");
    expect(names).toContain("system.health");
    expect(names).toContain("system.network");
    expect(names).toContain("process.list");
    expect(names).toContain("process.search");
    expect(names).toContain("process.details");
    expect(names).toContain("timeline.list");
    expect(names).toContain("timeline.search");

    const resources = await client.listResources();
    const uris = resources.resources.map((r) => r.uri);
    expect(uris).toContain("pulse://system/cpu");
    expect(uris).toContain("pulse://timeline/live");

    const self = await client.callTool({ name: "mcp.self", arguments: {} });
    const text = (self.content as Array<{ text?: string }>)[0]?.text ?? "";
    const body = JSON.parse(text) as {
      ok: boolean;
      data: { capabilities: { tools: string[] } };
    };
    expect(body.ok).toBe(true);
    expect(body.data.capabilities.tools).toContain("system.cpu");

    await client.close();
    await mcp.close();
  });

  it("system.cpu returns POLICY_DISABLED when off", async () => {
    const session = getSharedIpcSession();
    const health = getSharedHealthCache(session);
    const timeline = getSharedTimelineCache(session);
    const mcp = createPulseMcpServer({
      metrics: new MetricsRegistry(),
      policy: { enabled: false, path: "test-policy.json" },
      logger: new PulseMcpLogger(),
      session,
      health,
      timeline,
    });
    const [clientTransport, serverTransport] =
      InMemoryTransport.createLinkedPair();
    const client = new Client({ name: "test", version: "0.0.1" });
    await Promise.all([
      mcp.connect(serverTransport),
      client.connect(clientTransport),
    ]);
    const result = await client.callTool({
      name: "system.cpu",
      arguments: {},
    });
    expect(result.isError).toBe(true);
    const text = (result.content as Array<{ text?: string }>)[0]?.text ?? "";
    const body = JSON.parse(text) as { code: string };
    expect(body.code).toBe("POLICY_DISABLED");
    await client.close();
    await mcp.close();
  });
});
