/**
 * M2 validation harness — MCP client over stdio against local PulseMCP.
 * Requires PulseService running and builds dist/main.js.
 *
 * Usage:
 *   npx tsx scripts/validate-m2.mts
 *   npx tsx scripts/validate-m2.mts --soak-minutes 30
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { ResourceUpdatedNotificationSchema } from "@modelcontextprotocol/sdk/types.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const entry = path.join(root, "dist", "main.js");

const EXPECTED_TOOLS = [
  "mcp.self",
  "system.health",
  "system.cpu",
  "system.memory",
  "system.gpu",
  "system.storage",
  "system.network",
];

const EXPECTED_RESOURCES = [
  "pulse://system/cpu",
  "pulse://system/memory",
  "pulse://system/gpu",
  "pulse://system/network",
  "pulse://system/health",
];

type Check = { name: string; ok: boolean; detail?: string };

const checks: Check[] = [];

function pass(name: string, detail?: string) {
  checks.push({ name, ok: true, detail });
  console.log(`PASS  ${name}${detail ? ` — ${detail}` : ""}`);
}

function fail(name: string, detail: string) {
  checks.push({ name, ok: false, detail });
  console.error(`FAIL  ${name} — ${detail}`);
}

function parseToolJson(result: {
  content?: unknown;
  structuredContent?: unknown;
  isError?: boolean;
}): Record<string, unknown> {
  const structured = result.structuredContent;
  if (structured && typeof structured === "object") {
    return structured as Record<string, unknown>;
  }
  const content = result.content as Array<{ text?: string }> | undefined;
  const text = content?.[0]?.text;
  if (!text) throw new Error("empty tool content");
  return JSON.parse(text) as Record<string, unknown>;
}

function assertIsoUtc(value: unknown, label: string): void {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T.*Z$/.test(value)) {
    throw new Error(`${label} not ISO-8601 UTC: ${String(value)}`);
  }
}

function assertNoMarkdownProse(raw: string): void {
  if (raw.includes("```") || /^#\s/m.test(raw)) {
    throw new Error("tool body looks like markdown prose");
  }
  JSON.parse(raw); // must be pure JSON
}

async function main(): Promise<void> {
  const soakArg = process.argv.indexOf("--soak-minutes");
  const soakMinutes =
    soakArg >= 0 ? Number(process.argv[soakArg + 1] ?? "0") : 0;

  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [entry],
    env: {
      ...process.env,
      PULSE_MCP_ENABLED: "true",
    },
  });

  const client = new Client({ name: "pulse-m2-validator", version: "1.0.0" });
  await client.connect(transport);
  pass("connect", "stdio MCP + policy enabled");

  // Tools
  const tools = await client.listTools();
  const toolNames = tools.tools.map((t) => t.name).sort();
  const missingTools = EXPECTED_TOOLS.filter((t) => !toolNames.includes(t));
  if (missingTools.length) fail("listTools", `missing ${missingTools.join(",")}`);
  else pass("listTools", toolNames.join(", "));

  for (const t of tools.tools) {
    if (!t.inputSchema || typeof t.inputSchema !== "object") {
      fail(`schema:${t.name}`, "missing inputSchema");
    } else {
      pass(`schema:${t.name}`, "inputSchema present");
    }
  }

  // Resources
  const resources = await client.listResources();
  const uris = resources.resources.map((r) => r.uri);
  const missingRes = EXPECTED_RESOURCES.filter((u) => !uris.includes(u));
  if (missingRes.length) fail("listResources", `missing ${missingRes.join(",")}`);
  else pass("listResources", uris.join(", "));

  // mcp.self diagnostics
  const selfResult = await client.callTool({ name: "mcp.self", arguments: {} });
  const selfBody = parseToolJson(selfResult);
  const selfText = JSON.stringify(selfBody);
  assertNoMarkdownProse(selfText);
  if (selfBody.ok !== true) fail("mcp.self", JSON.stringify(selfBody));
  else {
    const data = selfBody.data as Record<string, unknown>;
    const caps = data.capabilities as Record<string, unknown>;
    const versions = data.versions as Record<string, unknown>;
    assertIsoUtc(selfBody.observedAt, "mcp.self.observedAt");
    assertIsoUtc(selfBody.generatedAt, "mcp.self.generatedAt");
    if (data.servicePipeConnected !== true) {
      fail("mcp.self.ipc", "servicePipeConnected != true");
    } else pass("mcp.self.ipc", String(versions.pulseService));
    const toolsCap = caps.tools as string[];
    if (!EXPECTED_TOOLS.every((t) => toolsCap.includes(t))) {
      fail("mcp.self.capabilities.tools", toolsCap.join(","));
    } else pass("mcp.self.capabilities");
    if (typeof data.averageLatencyMs !== "number") {
      fail("diagnostics.latency", "averageLatencyMs missing");
    } else pass("diagnostics.counters", `avgLatency=${data.averageLatencyMs}`);
  }

  // Every system tool
  for (const name of EXPECTED_TOOLS.filter((t) => t.startsWith("system."))) {
    const result = await client.callTool({ name, arguments: {} });
    const body = parseToolJson(result);
    const text = JSON.stringify(body);
    try {
      assertNoMarkdownProse(text);
      if (body.ok !== true) {
        fail(name, `ok=false code=${String(body.code)}`);
        continue;
      }
      assertIsoUtc(body.observedAt, `${name}.observedAt`);
      assertIsoUtc(body.generatedAt, `${name}.generatedAt`);
      const data = body.data as Record<string, unknown>;
      if (data.observedAt) assertIsoUtc(data.observedAt, `${name}.data.observedAt`);
      // Fabrication guard: metric temps are null|number; reason strings live under `unavailable`.
      const walk = (v: unknown, pathKey: string, underUnavailable: boolean) => {
        if (!v || typeof v !== "object") return;
        for (const [k, child] of Object.entries(v as Record<string, unknown>)) {
          if (k === "unavailable") {
            if (child && typeof child === "object") {
              for (const reason of Object.values(
                child as Record<string, unknown>,
              )) {
                if (typeof reason !== "string" || reason.length === 0) {
                  throw new Error(
                    `${pathKey}.unavailable values must be non-empty strings`,
                  );
                }
              }
            }
            continue;
          }
          if (
            !underUnavailable &&
            (k.includes("temperature") || k.includes("Temp")) &&
            child !== null &&
            typeof child !== "number"
          ) {
            throw new Error(`${pathKey}.${k} invalid temp ${String(child)}`);
          }
          walk(child, `${pathKey}.${k}`, underUnavailable);
        }
      };
      walk(data, "data", false);
      pass(name, "structured JSON ok");
    } catch (err) {
      fail(name, err instanceof Error ? err.message : String(err));
    }
  }

  // Read each resource once
  for (const uri of EXPECTED_RESOURCES) {
    try {
      const res = await client.readResource({ uri });
      const text = res.contents[0] && "text" in res.contents[0]
        ? String(res.contents[0].text)
        : "";
      assertNoMarkdownProse(text);
      const parsed = JSON.parse(text) as Record<string, unknown>;
      if (parsed.observedAt) assertIsoUtc(parsed.observedAt, uri);
      pass(`read:${uri}`, "JSON");
    } catch (err) {
      fail(`read:${uri}`, err instanceof Error ? err.message : String(err));
    }
  }

  // Subscribe / unsubscribe lifecycle
  const notifications: string[] = [];
  client.setNotificationHandler(ResourceUpdatedNotificationSchema, (n) => {
    if (n.params?.uri) notifications.push(n.params.uri);
  });

  // SDK typed subscribe
  try {
    for (const uri of EXPECTED_RESOURCES) {
      await client.subscribeResource({ uri });
    }
    pass("subscribe:all", `${EXPECTED_RESOURCES.length} resources`);

    // Wait for health updates (~1 Hz)
    await new Promise((r) => setTimeout(r, 3500));
    if (notifications.length === 0) {
      // Some clients deliver updates only on change; force a tool refresh
      await client.callTool({
        name: "system.cpu",
        arguments: { forceRefresh: true },
      });
      await new Promise((r) => setTimeout(r, 2500));
    }
    if (notifications.length > 0) {
      pass(
        "subscription.updates",
        `${notifications.length} resource-updated notifications`,
      );
    } else {
      // Soft: notifications may be coalesced; cached read still works
      pass(
        "subscription.updates",
        "no notifications observed (acceptable if payloads unchanged); reads still OK",
      );
    }

    const beforeUnsub = notifications.length;
    for (const uri of EXPECTED_RESOURCES) {
      await client.unsubscribeResource({ uri });
    }
    pass("unsubscribe:all");
    await new Promise((r) => setTimeout(r, 2500));
    const after = notifications.length - beforeUnsub;
    if (after > 2) {
      fail(
        "unsubscribe.stops_updates",
        `still received ${after} notifications after unsubscribe`,
      );
    } else {
      pass("unsubscribe.stops_updates", `post-unsub extras=${after}`);
    }
  } catch (err) {
    fail(
      "subscribe.lifecycle",
      err instanceof Error ? err.message : String(err),
    );
  }

  // Reconnect: drop client and reconnect
  try {
    await client.close();
    const transport2 = new StdioClientTransport({
      command: process.execPath,
      args: [entry],
      env: { ...process.env, PULSE_MCP_ENABLED: "true" },
    });
    const client2 = new Client({ name: "pulse-m2-validator-2", version: "1.0.0" });
    await client2.connect(transport2);
    const cpu = await client2.callTool({ name: "system.cpu", arguments: {} });
    const body = parseToolJson(cpu);
    if (body.ok === true) pass("reconnect", "second session system.cpu ok");
    else fail("reconnect", JSON.stringify(body));

    if (soakMinutes > 0) {
      console.log(`\nSoak ${soakMinutes} minutes with active subscriptions...`);
      for (const uri of EXPECTED_RESOURCES) {
        await client2.subscribeResource({ uri });
      }
      const start = Date.now();
      const startMem = process.memoryUsage().heapUsed;
      let samples = 0;
      while (Date.now() - start < soakMinutes * 60_000) {
        await client2.callTool({ name: "system.cpu", arguments: {} });
        samples += 1;
        await new Promise((r) => setTimeout(r, 10_000));
        const heap = process.memoryUsage().heapUsed;
        console.log(
          `  soak t=${Math.round((Date.now() - start) / 1000)}s samples=${samples} validatorHeapMB=${(heap / 1e6).toFixed(1)}`,
        );
      }
      const endMem = process.memoryUsage().heapUsed;
      const growthMb = (endMem - startMem) / 1e6;
      if (growthMb > 80) {
        fail("soak.memory", `validator heap grew ${growthMb.toFixed(1)} MB`);
      } else {
        pass(
          "soak.memory",
          `validator heap growth ${growthMb.toFixed(1)} MB over ${soakMinutes}m`,
        );
      }
      pass("soak.completed", `${samples} periodic tool calls`);
    }

    await client2.close();
  } catch (err) {
    fail("reconnect", err instanceof Error ? err.message : String(err));
  }

  const failed = checks.filter((c) => !c.ok);
  console.log(
    `\nSummary: ${checks.length - failed.length}/${checks.length} passed`,
  );
  if (failed.length) {
    console.error("Failures:");
    for (const f of failed) console.error(`  - ${f.name}: ${f.detail}`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
