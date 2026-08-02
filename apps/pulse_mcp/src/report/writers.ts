import PDFDocument from "pdfkit";

import { ReportExportError } from "./errors.js";
import type { ReportFormat, ReportModel, ReportType } from "./types.js";

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function kvRows(obj: Record<string, unknown>, prefix = ""): [string, string][] {
  const rows: [string, string][] = [];
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (v === null || v === undefined) {
      rows.push([key, ""]);
    } else if (typeof v === "object" && !Array.isArray(v)) {
      rows.push(...kvRows(v as Record<string, unknown>, key));
    } else if (Array.isArray(v)) {
      rows.push([key, `${v.length} items`]);
    } else {
      rows.push([key, String(v)]);
    }
  }
  return rows;
}

export function buildJson(model: ReportModel): Buffer {
  return Buffer.from(JSON.stringify(model, null, 2), "utf8");
}

export function buildCsv(template: ReportType, model: ReportModel): Buffer {
  if (template === "diagnostics") {
    throw new ReportExportError(
      "NOT_SUPPORTED",
      "CSV is not supported for diagnostics reports. Use json, html, pdf, or markdown.",
      { template, format: "csv" },
    );
  }

  const lines: string[] = [];
  const esc = (v: string) => `"${v.replace(/"/g, '""')}"`;

  if (template === "timeline" || template === "combined") {
    const events =
      (
        (model.sections.timeline as { events?: Record<string, unknown>[] })
          ?.events ?? []
      );
    lines.push(
      ["observedAt", "severity", "title", "channel", "provider", "eventId", "processName"].join(
        ",",
      ),
    );
    for (const e of events) {
      lines.push(
        [
          esc(String(e.observedAt ?? "")),
          esc(String(e.severity ?? "")),
          esc(String(e.title ?? "")),
          esc(String(e.channel ?? "")),
          esc(String(e.provider ?? "")),
          esc(String(e.eventId ?? "")),
          esc(String(e.processName ?? "")),
        ].join(","),
      );
    }
    if (template === "combined") {
      lines.push("");
      lines.push("section,key,value");
      for (const [k, v] of kvRows(
        (model.sections.health as Record<string, unknown>) ?? {},
      )) {
        lines.push(["health", esc(k), esc(v)].join(","));
      }
    }
    return Buffer.from(lines.join("\n") + "\n", "utf8");
  }

  if (template === "hardware") {
    lines.push("bus,id,description,manufacturer,hardwareId,className");
    const usb = (
      model.sections.usb as { devices?: Record<string, unknown>[] }
    )?.devices ?? [];
    const pci = (
      model.sections.pci as { devices?: Record<string, unknown>[] }
    )?.devices ?? [];
    for (const d of usb) {
      lines.push(
        [
          "usb",
          esc(String(d.id ?? "")),
          esc(String(d.description ?? "")),
          esc(String(d.manufacturer ?? "")),
          esc(String(d.hardwareId ?? "")),
          esc(String(d.className ?? "")),
        ].join(","),
      );
    }
    for (const d of pci) {
      lines.push(
        [
          "pci",
          esc(String(d.id ?? "")),
          esc(String(d.description ?? "")),
          esc(String(d.manufacturer ?? "")),
          esc(String(d.hardwareId ?? "")),
          esc(String(d.className ?? "")),
        ].join(","),
      );
    }
    return Buffer.from(lines.join("\n") + "\n", "utf8");
  }

  // health (and fallback)
  lines.push("key,value");
  for (const [k, v] of kvRows(
    (model.sections.health as Record<string, unknown>) ?? model.sections,
  )) {
    lines.push([esc(k), esc(v)].join(","));
  }
  return Buffer.from(lines.join("\n") + "\n", "utf8");
}

export function buildHtml(model: ReportModel): Buffer {
  const title = `Pulse — ${model.template}`;
  const identityRows = Object.entries(model.system_identity)
    .map(
      ([k, v]) =>
        `<tr><th>${escapeHtml(k)}</th><td>${escapeHtml(v)}</td></tr>`,
    )
    .join("\n");
  const bodyJson = escapeHtml(JSON.stringify(model.sections, null, 2));
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>${escapeHtml(title)}</title>
<style>
  body { font-family: Segoe UI, system-ui, sans-serif; background: #0f1115; color: #e8eaed;
         margin: 0; padding: 32px 40px; line-height: 1.45; }
  h1 { font-size: 28px; font-weight: 600; margin: 0 0 4px; }
  .brand { color: #4c8bf5; font-weight: 700; font-size: 14px; letter-spacing: 0.08em;
           text-transform: uppercase; margin-bottom: 12px; }
  .meta { color: #9aa0a6; font-size: 13px; margin-bottom: 28px; }
  section { background: #1a1d24; border: 1px solid #2a2f3a; border-radius: 10px;
            padding: 18px 20px; margin-bottom: 16px; }
  h2 { font-size: 15px; margin: 0 0 12px; font-weight: 600; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #2a2f3a; }
  th { color: #9aa0a6; font-weight: 500; width: 32%; }
  pre { white-space: pre-wrap; word-break: break-word; font-size: 12px; }
</style>
</head>
<body>
  <div class="brand">Pulse</div>
  <h1>${escapeHtml(model.template)} report</h1>
  <div class="meta">Exported ${escapeHtml(model.exported_at)} · Pulse ${escapeHtml(model.pulse_version)} · MCP ${escapeHtml(model.mcp_version)}</div>
  <section>
    <h2>System identity</h2>
    <table>${identityRows || "<tr><td>—</td></tr>"}</table>
  </section>
  <section>
    <h2>Sections</h2>
    <pre>${bodyJson}</pre>
  </section>
</body>
</html>
`;
  return Buffer.from(html, "utf8");
}

export function buildMarkdown(model: ReportModel): Buffer {
  const lines: string[] = [
    `# Pulse — ${model.template} report`,
    "",
    `Exported: ${model.exported_at}`,
    `Pulse: ${model.pulse_version} · MCP: ${model.mcp_version}`,
    "",
    "## System identity",
    "",
  ];
  for (const [k, v] of Object.entries(model.system_identity)) {
    lines.push(`- **${k}**: ${v}`);
  }
  if (Object.keys(model.system_identity).length === 0) {
    lines.push("- —");
  }
  lines.push("", "## Sections", "", "```json");
  lines.push(JSON.stringify(model.sections, null, 2));
  lines.push("```", "");
  return Buffer.from(lines.join("\n"), "utf8");
}

export async function buildPdf(model: ReportModel): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 48, size: "A4" });
    const chunks: Buffer[] = [];
    doc.on("data", (c: Buffer) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    doc.fillColor("#4c8bf5").fontSize(11).text("Pulse");
    doc.moveDown(0.3);
    doc.fillColor("#000000").fontSize(18).text(`${model.template} report`);
    doc
      .fontSize(9)
      .fillColor("#555555")
      .text(
        `Exported ${model.exported_at} · Pulse ${model.pulse_version} · MCP ${model.mcp_version}`,
      );
    doc.moveDown();
    doc.fillColor("#000000").fontSize(12).text("System identity");
    doc.moveDown(0.3);
    doc.fontSize(10);
    for (const [k, v] of Object.entries(model.system_identity)) {
      doc.text(`${k}: ${v}`);
    }
    if (Object.keys(model.system_identity).length === 0) {
      doc.text("—");
    }
    doc.moveDown();
    doc.fontSize(12).text("Sections (summary)");
    doc.moveDown(0.3);
    doc.fontSize(9);
    const summary = JSON.stringify(model.sections, null, 2);
    const clipped =
      summary.length > 12_000
        ? `${summary.slice(0, 12_000)}\n… [truncated for PDF size]`
        : summary;
    doc.text(clipped, { width: 500 });
    doc.end();
  });
}

export async function renderReportBytes(
  format: ReportFormat,
  template: ReportType,
  model: ReportModel,
): Promise<Buffer> {
  switch (format) {
    case "json":
      return buildJson(model);
    case "csv":
      return buildCsv(template, model);
    case "html":
      return buildHtml(model);
    case "markdown":
      return buildMarkdown(model);
    case "pdf":
      return buildPdf(model);
  }
}
