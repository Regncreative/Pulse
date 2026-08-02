export type ToolErrorCode =
  | "SERVICE_UNAVAILABLE"
  | "TIMEOUT"
  | "POLICY_DISABLED"
  | "INVALID_ARGUMENT"
  | "NOT_SUPPORTED"
  | "ACCESS_DENIED"
  | "INTERNAL_ERROR"
  /** @deprecated use INVALID_ARGUMENT */
  | "INVALID_ARGUMENTS"
  /** @deprecated use NOT_SUPPORTED */
  | "UNSUPPORTED"
  /** @deprecated use ACCESS_DENIED */
  | "PERMISSION_DENIED"
  /** @deprecated use INTERNAL_ERROR */
  | "INTERNAL"
  | "PROCESS_NOT_FOUND";

export interface SuccessEnvelope<T> {
  ok: true;
  tool: string;
  permission: "observation";
  observedAt: string;
  generatedAt: string;
  pulse: {
    serviceVersion: string | null;
    mcpVersion: string;
    ipcProtocolVersion: number;
  };
  data: T;
}

export interface ErrorEnvelope {
  ok: false;
  tool: string;
  code: ToolErrorCode;
  message: string;
  details: Record<string, unknown>;
  observedAt: string;
  generatedAt: string;
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function success<T>(
  tool: string,
  data: T,
  opts: {
    observedAt?: string;
    mcpVersion: string;
    ipcProtocolVersion: number;
    serviceVersion?: string | null;
  },
): SuccessEnvelope<T> {
  const generatedAt = nowIso();
  return {
    ok: true,
    tool,
    permission: "observation",
    observedAt: opts.observedAt ?? generatedAt,
    generatedAt,
    pulse: {
      serviceVersion: opts.serviceVersion ?? null,
      mcpVersion: opts.mcpVersion,
      ipcProtocolVersion: opts.ipcProtocolVersion,
    },
    data,
  };
}

export function failure(
  tool: string,
  code: ToolErrorCode,
  message: string,
  details: Record<string, unknown> = {},
  observedAt?: string,
): ErrorEnvelope {
  const generatedAt = nowIso();
  return {
    ok: false,
    tool,
    code,
    message,
    details,
    observedAt: observedAt ?? generatedAt,
    generatedAt,
  };
}

/** MCP tool result: JSON only (no markdown/prose). */
export function toMcpToolResult(body: SuccessEnvelope<unknown> | ErrorEnvelope) {
  const text = JSON.stringify(body);
  return {
    content: [{ type: "text" as const, text }],
    structuredContent: body as unknown as Record<string, unknown>,
    isError: body.ok === false,
  };
}
