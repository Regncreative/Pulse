import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";

import { ReportExportError } from "./errors.js";
import { gatherReportData, type GatherDeps } from "./gather.js";
import { buildReportModel } from "./model.js";
import { getSharedTempReportStore, type TempReportStore } from "./temp.js";
import {
  extensionFor,
  fileStemFor,
  REPORT_FORMATS,
  REPORT_TYPES,
  type ReportExportArgs,
  type ReportExportResult,
  type ReportFilters,
  type ReportFormat,
  type ReportType,
} from "./types.js";
import { renderReportBytes } from "./writers.js";

function parseReportType(raw: string | undefined): ReportType {
  const v = (raw ?? "").trim().toLowerCase();
  if ((REPORT_TYPES as readonly string[]).includes(v)) {
    return v as ReportType;
  }
  // Flutter / alias names
  if (v === "healthsnapshot" || v === "health_snapshot") return "health";
  if (v === "hardwareinventory" || v === "hardware_inventory") return "hardware";
  throw new ReportExportError(
    "INVALID_REPORT_TYPE",
    `Invalid report type '${raw ?? ""}'. Supported: ${REPORT_TYPES.join(", ")}.`,
    { reportType: raw ?? null, supported: [...REPORT_TYPES] },
  );
}

function parseFormat(raw: string | undefined): ReportFormat {
  const v = (raw ?? "").trim().toLowerCase();
  if (v === "md") return "markdown";
  if ((REPORT_FORMATS as readonly string[]).includes(v)) {
    return v as ReportFormat;
  }
  throw new ReportExportError(
    "INVALID_FORMAT",
    `Invalid format '${raw ?? ""}'. Supported: ${REPORT_FORMATS.join(", ")}.`,
    { format: raw ?? null, supported: [...REPORT_FORMATS] },
  );
}

function defaultReportsDir(): string {
  return path.join(os.homedir(), "Documents", "Pulse", "Reports");
}

function stamp(): string {
  return new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
}

async function resolveOutputPath(opts: {
  format: ReportFormat;
  template: ReportType;
  reportId: string;
  outputPath?: string;
  directory?: string;
  tempStore: TempReportStore;
}): Promise<{ absolutePath: string; temporary: boolean }> {
  const ext = extensionFor(opts.format);
  const fileName = `${fileStemFor(opts.template)}-${stamp()}-${opts.reportId.slice(0, 8)}.${ext}`;

  if (opts.outputPath && opts.outputPath.trim()) {
    const raw = path.resolve(opts.outputPath.trim());
    const looksLikeFile = /\.[a-z0-9]+$/i.test(path.basename(raw));
    if (looksLikeFile) {
      await fs.mkdir(path.dirname(raw), { recursive: true });
      return { absolutePath: raw, temporary: false };
    }
    await fs.mkdir(raw, { recursive: true });
    return { absolutePath: path.join(raw, fileName), temporary: false };
  }

  if (opts.directory && opts.directory.trim()) {
    const dir = path.resolve(opts.directory.trim());
    await fs.mkdir(dir, { recursive: true });
    return { absolutePath: path.join(dir, fileName), temporary: false };
  }

  const tempRoot = await opts.tempStore.ensureRoot();
  return {
    absolutePath: path.join(tempRoot, fileName),
    temporary: true,
  };
}

export async function runReportExport(
  deps: GatherDeps,
  args: ReportExportArgs,
  tempStore: TempReportStore = getSharedTempReportStore(),
): Promise<ReportExportResult> {
  const template = parseReportType(args.reportType ?? args.template);
  const format = parseFormat(args.format);
  const filters: ReportFilters = args.filters ?? {};
  const reportId = randomUUID();

  try {
    await tempStore.cleanupExpired();
    const data = await gatherReportData(deps, template, filters);
    const model = buildReportModel(template, data);
    const bytes = await renderReportBytes(format, template, model);
    const { absolutePath, temporary } = await resolveOutputPath({
      format,
      template,
      reportId,
      outputPath: args.outputPath,
      directory: args.directory,
      tempStore,
    });

    try {
      await fs.writeFile(absolutePath, bytes);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (/EACCES|EPERM|access/i.test(msg)) {
        throw new ReportExportError(
          "ACCESS_DENIED",
          `Cannot write report to ${absolutePath}: ${msg}`,
          { path: absolutePath },
        );
      }
      throw new ReportExportError(
        "EXPORT_FAILED",
        `Failed to write report: ${msg}`,
        { path: absolutePath },
      );
    }

    const createdAt = new Date().toISOString();
    if (temporary) {
      tempStore.track(reportId, absolutePath);
    }

    // Prefer default Documents path metadata when neither path nor directory given?
    // Temp is correct per requirements.
    void defaultReportsDir;

    return {
      reportId,
      template,
      format,
      path: absolutePath,
      bytes: bytes.length,
      createdAt,
      temporary,
      sideEffects: ["write_user_export_dir"],
    };
  } catch (err) {
    if (err instanceof ReportExportError) throw err;
    const msg = err instanceof Error ? err.message : String(err);
    throw new ReportExportError("EXPORT_FAILED", msg);
  }
}
