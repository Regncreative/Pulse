import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export type LogLevel = "debug" | "info" | "warn" | "error";

function defaultLogDir(): string {
  const base =
    process.env.LOCALAPPDATA ??
    process.env.XDG_STATE_HOME ??
    path.join(os.homedir(), ".local", "state");
  return path.join(base, "Pulse", "logs", "pulsemcp");
}

export class PulseMcpLogger {
  readonly logPath: string;
  private readonly stream: fs.WriteStream;

  constructor(logDir = process.env.PULSE_MCP_LOG_DIR ?? defaultLogDir()) {
    fs.mkdirSync(logDir, { recursive: true });
    const day = new Date().toISOString().slice(0, 10).replace(/-/g, "");
    this.logPath = path.join(logDir, `pulsemcp-${day}.jsonl`);
    this.stream = fs.createWriteStream(this.logPath, { flags: "a" });
  }

  log(level: LogLevel, message: string, fields: Record<string, unknown> = {}): void {
    const line = JSON.stringify({
      ts: new Date().toISOString(),
      level,
      component: "PulseMCP",
      message,
      ...fields,
    });
    this.stream.write(`${line}\n`);
    // MCP stdio: never write to stdout.
    console.error(line);
  }

  info(message: string, fields?: Record<string, unknown>): void {
    this.log("info", message, fields);
  }

  warn(message: string, fields?: Record<string, unknown>): void {
    this.log("warn", message, fields);
  }

  error(message: string, fields?: Record<string, unknown>): void {
    this.log("error", message, fields);
  }

  close(): void {
    this.stream.end();
  }
}
