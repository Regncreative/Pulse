/**
 * M3 validation harness — process_list / search / details over stdio MCP.
 *
 * Usage: npx tsx scripts/validate-m3.mts
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const entry = path.join(root, "dist", "main.js");

const EXPECTED_PROCESS_TOOLS = [
  "process_list",
  "process_search",
  "process_details",
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

async function main(): Promise<void> {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [entry],
    env: { ...process.env, PULSE_MCP_ENABLED: "true" },
  });
  const client = new Client({ name: "pulse-m3-validator", version: "1.0.0" });
  await client.connect(transport);
  pass("connect");

  const tools = await client.listTools();
  const names = tools.tools.map((t) => t.name);
  for (const t of EXPECTED_PROCESS_TOOLS) {
    if (!names.includes(t)) fail(`listTools:${t}`, "missing");
    else pass(`listTools:${t}`);
  }

  const self = parseToolJson(
    await client.callTool({ name: "mcp_self", arguments: {} }),
  );
  if (self.ok !== true) fail("mcp_self", JSON.stringify(self));
  else {
    const data = self.data as Record<string, unknown>;
    const caps = data.capabilities as Record<string, unknown>;
    const toolCaps = caps.tools as string[];
    const namespaces = data.namespaces as string[];
    if (!namespaces.includes("process")) fail("mcp_self.namespaces", "no process");
    else pass("mcp_self.namespaces", "process");
    for (const t of EXPECTED_PROCESS_TOOLS) {
      if (!toolCaps.includes(t)) fail(`mcp_self.capabilities:${t}`, "missing");
      else pass(`mcp_self.capabilities:${t}`);
    }
    if (data.servicePipeConnected !== true) fail("mcp_self.ipc", "disconnected");
    else pass("mcp_self.ipc");
  }

  // process_list
  const listBody = parseToolJson(
    await client.callTool({
      name: "process_list",
      arguments: { limit: 25, sortBy: "cpu", sortDir: "desc" },
    }),
  );
  try {
    if (listBody.ok !== true) throw new Error(`ok=false ${listBody.code}`);
    assertIsoUtc(listBody.observedAt, "list.observedAt");
    const data = listBody.data as Record<string, unknown>;
    assertIsoUtc(data.observedAt, "list.data.observedAt");
    if (typeof data.count !== "number" || data.count < 1) {
      throw new Error(`count=${String(data.count)}`);
    }
    const processes = data.processes as Array<Record<string, unknown>>;
    if (!Array.isArray(processes) || processes.length < 1) {
      throw new Error("empty processes");
    }
    const row = processes[0]!;
    if (typeof row.pid !== "number" || typeof row.id !== "string") {
      throw new Error("row missing pid/id");
    }
    pass("process_list", `count=${data.count}`);
  } catch (err) {
    fail("process_list", err instanceof Error ? err.message : String(err));
  }

  // process_search
  const searchBody = parseToolJson(
    await client.callTool({
      name: "process_search",
      arguments: { query: "node", limit: 20 },
    }),
  );
  try {
    if (searchBody.ok !== true) throw new Error(`ok=false ${searchBody.code}`);
    const data = searchBody.data as Record<string, unknown>;
    assertIsoUtc(data.observedAt, "search.observedAt");
    if (data.query !== "node") throw new Error("query echo mismatch");
    if (typeof data.count !== "number") throw new Error("count missing");
    pass("process_search", `count=${data.count}`);
  } catch (err) {
    fail("process_search", err instanceof Error ? err.message : String(err));
  }

  // process_details — current node pid
  const detailsBody = parseToolJson(
    await client.callTool({
      name: "process_details",
      arguments: { pid: process.pid },
    }),
  );
  try {
    if (detailsBody.ok !== true) throw new Error(`ok=false ${detailsBody.code}`);
    const data = detailsBody.data as Record<string, unknown>;
    assertIsoUtc(data.observedAt, "details.observedAt");
    if (data.pid !== process.pid) throw new Error(`pid=${String(data.pid)}`);
    if (data.commandLine && String(data.commandLine).includes("password=")) {
      throw new Error("unredacted secret pattern in cmdline");
    }
    pass("process_details", `pid=${data.pid} name=${String(data.name)}`);
  } catch (err) {
    fail("process_details", err instanceof Error ? err.message : String(err));
  }

  // PROCESS_NOT_FOUND
  const missing = parseToolJson(
    await client.callTool({
      name: "process_details",
      arguments: { pid: 2147483646 },
    }),
  );
  if (missing.ok === false && missing.code === "PROCESS_NOT_FOUND") {
    pass("process_details.not_found", "PROCESS_NOT_FOUND");
  } else {
    fail(
      "process_details.not_found",
      `expected PROCESS_NOT_FOUND got ${JSON.stringify(missing)}`,
    );
  }

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
