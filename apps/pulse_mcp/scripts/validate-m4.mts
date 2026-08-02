/**
 * M4 validation — timeline_list / search + pulse://timeline/live subscribe.
 *
 * Usage: npx tsx scripts/validate-m4.mts
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { ResourceUpdatedNotificationSchema } from "@modelcontextprotocol/sdk/types.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const entry = path.join(root, "dist", "main.js");

const TIMELINE_LIVE = "pulse://timeline/live";

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
}): Record<string, unknown> {
  if (result.structuredContent && typeof result.structuredContent === "object") {
    return result.structuredContent as Record<string, unknown>;
  }
  const text = (result.content as Array<{ text?: string }> | undefined)?.[0]
    ?.text;
  if (!text) throw new Error("empty tool content");
  return JSON.parse(text) as Record<string, unknown>;
}

async function main(): Promise<void> {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [entry],
    env: { ...process.env, PULSE_MCP_ENABLED: "true" },
  });
  const client = new Client({ name: "pulse-m4-validator", version: "1.0.0" });
  await client.connect(transport);
  pass("connect");

  const tools = await client.listTools();
  const names = tools.tools.map((t) => t.name);
  for (const t of ["timeline_list", "timeline_search"]) {
    if (names.includes(t)) pass(`listTools:${t}`);
    else fail(`listTools:${t}`, "missing");
  }

  const resources = await client.listResources();
  const uris = resources.resources.map((r) => r.uri);
  if (uris.includes(TIMELINE_LIVE)) pass("listResources:timeline/live");
  else fail("listResources:timeline/live", "missing");

  const self = parseToolJson(
    await client.callTool({ name: "mcp_self", arguments: {} }),
  );
  const data = self.data as Record<string, unknown>;
  const caps = data.capabilities as Record<string, unknown>;
  const namespaces = data.namespaces as string[];
  if (namespaces.includes("timeline")) pass("mcp_self.namespaces");
  else fail("mcp_self.namespaces", "no timeline");
  const toolCaps = caps.tools as string[];
  if (toolCaps.includes("timeline_list") && toolCaps.includes("timeline_search")) {
    pass("mcp_self.capabilities.tools");
  } else fail("mcp_self.capabilities.tools", toolCaps.join(","));
  const subs = caps.subscriptions as string[];
  if (subs.includes(TIMELINE_LIVE)) pass("mcp_self.capabilities.subscriptions");
  else fail("mcp_self.capabilities.subscriptions", "missing live");

  const listBody = parseToolJson(
    await client.callTool({
      name: "timeline_list",
      arguments: { limit: 20 },
    }),
  );
  try {
    if (listBody.ok !== true) throw new Error(String(listBody.code));
    const d = listBody.data as Record<string, unknown>;
    if (typeof d.count !== "number" || d.count < 1) {
      throw new Error(`count=${String(d.count)}`);
    }
    const events = d.events as Array<Record<string, unknown>>;
    if (events[0]?.rawXml !== undefined) {
      throw new Error("rawXml present without includeRaw");
    }
    pass(
      "timeline_list",
      `count=${d.count} securityAvailable=${String(d.securityChannelAvailable)}`,
    );
  } catch (err) {
    fail("timeline_list", err instanceof Error ? err.message : String(err));
  }

  const searchBody = parseToolJson(
    await client.callTool({
      name: "timeline_search",
      arguments: { severity: ["error", "critical", "warning"], limit: 15 },
    }),
  );
  try {
    if (searchBody.ok !== true) throw new Error(String(searchBody.code));
    const d = searchBody.data as Record<string, unknown>;
    pass("timeline_search", `count=${d.count}`);
  } catch (err) {
    fail("timeline_search", err instanceof Error ? err.message : String(err));
  }

  // Security channel honesty — ACCESS_DENIED is acceptable when unreadable.
  const sec = parseToolJson(
    await client.callTool({
      name: "timeline_search",
      arguments: { channel: "security", limit: 5 },
    }),
  );
  if (sec.ok === true) {
    pass("timeline.security", "accessible");
  } else if (sec.code === "ACCESS_DENIED") {
    pass("timeline.security", "ACCESS_DENIED (honest)");
  } else {
    fail("timeline.security", JSON.stringify(sec));
  }

  const notifications: string[] = [];
  client.setNotificationHandler(ResourceUpdatedNotificationSchema, (n) => {
    if (n.params?.uri) notifications.push(n.params.uri);
  });

  await client.subscribeResource({ uri: TIMELINE_LIVE });
  pass("subscribe:timeline/live");
  await new Promise((r) => setTimeout(r, 8000));
  if (notifications.some((u) => u === TIMELINE_LIVE)) {
    pass(
      "subscription.updates",
      `${notifications.filter((u) => u === TIMELINE_LIVE).length} updates`,
    );
  } else {
    // Quiet systems may not emit events in 8s — read still ok.
    const read = await client.readResource({ uri: TIMELINE_LIVE });
    const text =
      read.contents[0] && "text" in read.contents[0]
        ? String(read.contents[0].text)
        : "";
    JSON.parse(text);
    pass(
      "subscription.updates",
      "no live events in window (acceptable); resource read ok",
    );
  }

  await client.unsubscribeResource({ uri: TIMELINE_LIVE });
  pass("unsubscribe:timeline/live");

  await client.close();
  const failed = checks.filter((c) => !c.ok);
  console.log(
    `\nSummary: ${checks.length - failed.length}/${checks.length} passed`,
  );
  if (failed.length) {
    for (const f of failed) console.error(`  - ${f.name}: ${f.detail}`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
