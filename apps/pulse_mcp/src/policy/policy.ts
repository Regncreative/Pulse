import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export interface McpPolicy {
  enabled: boolean;
  path: string;
}

function defaultPolicyPath(): string {
  const base = process.env.LOCALAPPDATA ?? path.join(os.homedir(), "AppData", "Local");
  return path.join(base, "Pulse", "mcp", "policy.json");
}

/**
 * Loads MCP bridge policy.
 *
 * Precedence:
 * 1. PULSE_MCP_ENABLED=true|false
 * 2. PULSE_MCP_POLICY_PATH or default policy.json `{ "enabled": bool }`
 * 3. Default: enabled=false (opt-in)
 */
export function loadPolicy(
  policyPath = process.env.PULSE_MCP_POLICY_PATH ?? defaultPolicyPath(),
): McpPolicy {
  const env = process.env.PULSE_MCP_ENABLED;
  if (env === "true" || env === "1") {
    return { enabled: true, path: policyPath };
  }
  if (env === "false" || env === "0") {
    return { enabled: false, path: policyPath };
  }

  try {
    if (!fs.existsSync(policyPath)) {
      return { enabled: false, path: policyPath };
    }
    const raw = JSON.parse(fs.readFileSync(policyPath, "utf8")) as {
      enabled?: unknown;
    };
    return { enabled: raw.enabled === true, path: policyPath };
  } catch {
    return { enabled: false, path: policyPath };
  }
}

export function writePolicy(enabled: boolean, policyPath: string): void {
  fs.mkdirSync(path.dirname(policyPath), { recursive: true });
  fs.writeFileSync(
    policyPath,
    `${JSON.stringify({ enabled, updatedAt: new Date().toISOString() }, null, 2)}\n`,
    "utf8",
  );
}
