import type { ToolErrorCode } from "../response/envelope.js";

export type ReportErrorCode =
  | "INVALID_REPORT_TYPE"
  | "INVALID_FORMAT"
  | "EXPORT_FAILED"
  | "ACCESS_DENIED"
  | "NOT_SUPPORTED";

export class ReportExportError extends Error {
  constructor(
    readonly code: ReportErrorCode,
    message: string,
    readonly details: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = "ReportExportError";
  }
}

export function toToolErrorCode(code: ReportErrorCode): ToolErrorCode {
  // Map report-specific codes into the envelope union (extended below).
  return code as unknown as ToolErrorCode;
}
