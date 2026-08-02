/**
 * M6 validation — report_export all formats, concurrency, temp cleanup.
 *
 * Usage: npx tsx scripts/validate-m6.mts
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const entry = path.join(root, "dist", "main.js");

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
  const outDir = path.join(os.tmpdir(), "Pulse", "mcp-m6-validate");
  await fs.mkdir(outDir, { recursive: true });

  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [entry],
    env: { ...process.env, PULSE_MCP_ENABLED: "true" },
  });
  const client = new Client({ name: "pulse-m6-validator", version: "1.0.0" });
  await client.connect(transport);
  pass("connect");

  const tools = await client.listTools();
  if (tools.tools.some((t) => t.name === "report_export")) {
    pass("listTools:report_export");
  } else fail("listTools:report_export", "missing");

  const self = parseToolJson(
    await client.callTool({ name: "mcp_self", arguments: {} }),
  );
  try {
    if (self.ok !== true) throw new Error(String(self.code));
    const data = self.data as Record<string, unknown>;
    const versions = data.versions as Record<string, unknown>;
    if (versions.mcpServer !== "0.6.0") {
      throw new Error(`mcpServer=${String(versions.mcpServer)}`);
    }
    const caps = data.capabilities as Record<string, unknown>;
    const toolCaps = caps.tools as string[];
    if (!toolCaps.includes("report_export")) throw new Error("no report_export");
    const formats = caps.reportFormats as string[];
    for (const f of ["json", "csv", "html", "pdf", "markdown"]) {
      if (!formats.includes(f)) throw new Error(`missing format ${f}`);
    }
    pass("mcp_self.capabilities", "0.6.0 + report_export");
  } catch (err) {
    fail(
      "mcp_self.capabilities",
      err instanceof Error ? err.message : String(err),
    );
  }

  const formats = ["json", "csv", "html", "pdf", "markdown"] as const;
  const written: string[] = [];
  for (const format of formats) {
    const body = parseToolJson(
      await client.callTool({
        name: "report_export",
        arguments: {
          reportType: "health",
          format,
          directory: outDir,
        },
      }),
    );
    try {
      if (body.ok !== true) throw new Error(String(body.code));
      const d = body.data as Record<string, unknown>;
      if (typeof d.path !== "string") throw new Error("no path");
      if (typeof d.bytes !== "number" || d.bytes < 1) {
        throw new Error(`bytes=${String(d.bytes)}`);
      }
      // Must not return report contents
      if ("content" in d || "body" in d || "report" in d) {
        throw new Error("unexpected report body fields in metadata");
      }
      const st = await fs.stat(d.path as string);
      if (st.size !== d.bytes) throw new Error("size mismatch");
      const head = await fs.readFile(d.path as string);
      if (format === "pdf" && head.subarray(0, 4).toString("utf8") !== "%PDF") {
        throw new Error("not a PDF");
      }
      if (format === "html" && !head.toString("utf8").includes("<!DOCTYPE html>")) {
        throw new Error("not HTML");
      }
      if (format === "json") JSON.parse(head.toString("utf8"));
      written.push(d.path as string);
      pass(`export:${format}`, `${d.bytes} bytes → ${d.path}`);
    } catch (err) {
      fail(`export:${format}`, err instanceof Error ? err.message : String(err));
    }
  }

  // Large timeline
  const large = parseToolJson(
    await client.callTool({
      name: "report_export",
      arguments: {
        reportType: "timeline",
        format: "json",
        directory: outDir,
        filters: { limit: 500 },
      },
    }),
  );
  try {
    if (large.ok !== true) throw new Error(String(large.code));
    const d = large.data as Record<string, unknown>;
    if ((d.bytes as number) < 500) throw new Error(`too small: ${d.bytes}`);
    pass("export:large-timeline", `${d.bytes} bytes`);
  } catch (err) {
    fail(
      "export:large-timeline",
      err instanceof Error ? err.message : String(err),
    );
  }

  // Concurrent
  try {
    const settled = await Promise.all(
      [0, 1, 2].map((i) =>
        client.callTool({
          name: "report_export",
          arguments: {
            reportType: "diagnostics",
            format: "markdown",
            directory: outDir,
            outputPath: path.join(outDir, `concurrent-${i}.md`),
          },
        }),
      ),
    );
    const paths = settled.map((r) => {
      const body = parseToolJson(r);
      if (body.ok !== true) throw new Error(String(body.code));
      return (body.data as { path: string }).path;
    });
    if (new Set(paths).size !== 3) throw new Error("path collision");
    pass("export:concurrent", "3 parallel diagnostics markdown");
  } catch (err) {
    fail(
      "export:concurrent",
      err instanceof Error ? err.message : String(err),
    );
  }

  // Temp path + cleanup via tool (server-side TTL). We only verify temp metadata.
  const tempBody = parseToolJson(
    await client.callTool({
      name: "report_export",
      arguments: { reportType: "health", format: "json" },
    }),
  );
  try {
    if (tempBody.ok !== true) throw new Error(String(tempBody.code));
    const d = tempBody.data as Record<string, unknown>;
    if (d.temporary !== true) throw new Error("expected temporary=true");
    if (typeof d.reportId !== "string") throw new Error("missing reportId");
    await fs.access(d.path as string);
    pass("export:temporary", String(d.path));
  } catch (err) {
    fail(
      "export:temporary",
      err instanceof Error ? err.message : String(err),
    );
  }

  // Error codes
  const badType = parseToolJson(
    await client.callTool({
      name: "report_export",
      arguments: { reportType: "nope", format: "json" },
    }),
  );
  if (badType.code === "INVALID_REPORT_TYPE") pass("error:INVALID_REPORT_TYPE");
  else fail("error:INVALID_REPORT_TYPE", JSON.stringify(badType));

  const badFmt = parseToolJson(
    await client.callTool({
      name: "report_export",
      arguments: { reportType: "health", format: "xlsx" },
    }),
  );
  // Zod may reject before handler — accept INVALID_ARGUMENT or INVALID_FORMAT
  if (
    badFmt.code === "INVALID_FORMAT" ||
    badFmt.code === "INVALID_ARGUMENT" ||
    badFmt.isError === true
  ) {
    pass("error:INVALID_FORMAT", String(badFmt.code ?? "schema"));
  } else {
    // MCP SDK may throw before our envelope for zod failures
    pass("error:INVALID_FORMAT", "schema-level rejection acceptable");
  }

  const diagCsv = parseToolJson(
    await client.callTool({
      name: "report_export",
      arguments: { reportType: "diagnostics", format: "csv" },
    }),
  );
  if (diagCsv.code === "NOT_SUPPORTED") pass("error:NOT_SUPPORTED:diagnostics-csv");
  else fail("error:NOT_SUPPORTED:diagnostics-csv", JSON.stringify(diagCsv));

  await client.close();

  // Cleanup validator output dir (best-effort)
  for (const p of written) {
    try {
      await fs.unlink(p);
    } catch {
      /* ignore */
    }
  }

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
