import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { describe, expect, it } from "vitest";

import { PulseMcpLogger } from "../src/logging/logger.js";
import { MetricsRegistry } from "../src/metrics/metrics.js";
import { createPulseMcpServer } from "../src/server/createServer.js";
import os from "node:os";
import path from "node:path";

describe("MCP integration", () => {
  it("lists mcp.self and calls it under enabled policy", async () => {
    const logDir = path.join(os.tmpdir(), `pulsemcp-test-${Date.now()}`);
    const logger = new PulseMcpLogger(logDir);
    const metrics = new MetricsRegistry();
    const server = createPulseMcpServer({
      metrics,
      policy: { enabled: true, path: "test.json" },
      logger,
    });

    const [clientTransport, serverTransport] =
      InMemoryTransport.createLinkedPair();
    const client = new Client({ name: "test", version: "0.0.1" });

    await server.connect(serverTransport);
    await client.connect(clientTransport);

    const tools = await client.listTools();
    expect(tools.tools.some((t) => t.name === "mcp.self")).toBe(true);

    const call = await client.callTool({ name: "mcp.self", arguments: {} });
    const text = (call.content as { type: string; text: string }[])[0]!.text;
    const body = JSON.parse(text) as {
      ok: boolean;
      data: { capabilities: { tools: string[] }; versions: { mcpServer: string } };
    };
    expect(body.ok).toBe(true);
    expect(body.data.versions.mcpServer).toBe("0.1.0");
    expect(body.data.capabilities.tools).toContain("mcp.self");

    await client.close();
    logger.close();
  });
});
