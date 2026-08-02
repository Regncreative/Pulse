/**
 * Removes Pulse-created AI client MCP registrations (uninstall / repair).
 * Only touches entries marked registeredByPulse in client-registrations.json.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function registrationsPath(): string {
  const base =
    process.env.LOCALAPPDATA ?? path.join(os.homedir(), "AppData", "Local");
  return path.join(base, "Pulse", "mcp", "client-registrations.json");
}

function backup(file: string): string | null {
  if (!fs.existsSync(file)) return null;
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const dest = `${file}.pulse-backup-${stamp}`;
  fs.copyFileSync(file, dest);
  return dest;
}

function removeServerKey(configPath: string, serverKey: string): boolean {
  if (!fs.existsSync(configPath)) return false;
  backup(configPath);
  const raw = fs.readFileSync(configPath, "utf8");
  let root: Record<string, unknown>;
  try {
    root = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return false;
  }
  const servers = root.mcpServers;
  if (!servers || typeof servers !== "object") return false;
  const map = { ...(servers as Record<string, unknown>) };
  if (!(serverKey in map)) return false;
  delete map[serverKey];
  root.mcpServers = map;
  const encoded = `${JSON.stringify(root, null, 2)}\n`;
  JSON.parse(encoded);
  fs.writeFileSync(configPath, encoded, "utf8");
  return true;
}

export function cleanupPulseRegistrations(): {
  removed: string[];
  skipped: string[];
} {
  const removed: string[] = [];
  const skipped: string[] = [];
  const regPath = registrationsPath();
  if (!fs.existsSync(regPath)) {
    return { removed, skipped };
  }
  let root: Record<string, unknown>;
  try {
    root = JSON.parse(fs.readFileSync(regPath, "utf8")) as Record<
      string,
      unknown
    >;
  } catch {
    return { removed, skipped };
  }

  for (const [client, value] of Object.entries(root)) {
    if (!value || typeof value !== "object") continue;
    const entry = value as Record<string, unknown>;
    if (entry.registeredByPulse !== true) {
      skipped.push(client);
      continue;
    }
    const configPath = String(entry.configPath ?? "");
    const serverKey = String(entry.serverKey ?? "pulse");
    if (!configPath) {
      skipped.push(client);
      continue;
    }
    if (removeServerKey(configPath, serverKey)) {
      removed.push(client);
      entry.registeredByPulse = false;
    } else {
      skipped.push(client);
    }
  }
  fs.writeFileSync(regPath, `${JSON.stringify(root, null, 2)}\n`, "utf8");
  return { removed, skipped };
}
