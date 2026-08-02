export const REPORT_TYPES = [
  "health",
  "timeline",
  "diagnostics",
  "hardware",
  "combined",
] as const;

export type ReportType = (typeof REPORT_TYPES)[number];

export const REPORT_FORMATS = [
  "json",
  "csv",
  "html",
  "pdf",
  "markdown",
] as const;

export type ReportFormat = (typeof REPORT_FORMATS)[number];

export interface ReportFilters {
  limit?: number;
  channel?: "system" | "application" | "security" | "other";
  severity?: string[];
  keyword?: string;
  from?: string;
  to?: string;
}

export interface ReportExportArgs {
  /** Doc 33 alias for reportType. */
  template?: string;
  reportType?: string;
  format?: string;
  /** Output file path or directory. */
  outputPath?: string;
  /** Doc 33 alias for directory-only output. */
  directory?: string;
  filters?: ReportFilters;
}

export interface ReportModel {
  pulse_export: string;
  template: ReportType;
  version: 1;
  exported_at: string;
  pulse_version: string;
  mcp_version: string;
  system_identity: Record<string, string>;
  sections: Record<string, unknown>;
}

export interface ReportExportResult {
  reportId: string;
  template: ReportType;
  format: ReportFormat;
  path: string;
  bytes: number;
  createdAt: string;
  temporary: boolean;
  sideEffects: ["write_user_export_dir"];
}

export function fileStemFor(template: ReportType): string {
  switch (template) {
    case "health":
      return "pulse-health";
    case "timeline":
      return "pulse-timeline";
    case "diagnostics":
      return "pulse-diagnostics";
    case "hardware":
      return "pulse-hardware";
    case "combined":
      return "pulse-combined";
  }
}

export function extensionFor(format: ReportFormat): string {
  return format === "markdown" ? "md" : format;
}
