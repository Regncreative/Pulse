export type ToolErrorCode =
  | "SERVICE_UNAVAILABLE"
  | "TIMEOUT"
  | "INVALID_ARGUMENTS"
  | "PROCESS_NOT_FOUND"
  | "PERMISSION_DENIED"
  | "POLICY_DISABLED"
  | "UNSUPPORTED"
  | "INTERNAL";

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

/** MCP tool result: JSON text + structuredContent for capable clients. */
export function toMcpToolResult(body: SuccessEnvelope<unknown> | ErrorEnvelope) {
  const text = JSON.stringify(body, null, 2);
  return {
    content: [{ type: "text" as const, text }],
    structuredContent: body as unknown as Record<string, unknown>,
    isError: body.ok === false,
  };
}
