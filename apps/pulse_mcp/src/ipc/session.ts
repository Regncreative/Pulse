import net from "node:net";

import {
  CLIENT_NAME,
  IPC_PROTOCOL_VERSION,
  MCP_SERVER_VERSION,
  PIPE_NAME,
} from "../version.js";
import { encodeFrame, tryDecodeFrame } from "./framing.js";
import {
  decodeEnvelope,
  encodeEnvelope,
  type Body,
  type Envelope,
} from "./wire.js";

export type IpcErrorCode =
  | "SERVICE_UNAVAILABLE"
  | "TIMEOUT"
  | "INTERNAL_ERROR";

export class PulseIpcError extends Error {
  constructor(
    message: string,
    readonly code: IpcErrorCode,
  ) {
    super(message);
    this.name = "PulseIpcError";
  }
}

type Pending = {
  resolve: (env: Envelope) => void;
  reject: (err: Error) => void;
  timer: NodeJS.Timeout;
};

export type PushHandler = (env: Envelope) => void;

/**
 * One persistent named-pipe session per PulseMCP process.
 * Reconnects only after disconnect; never opens a new pipe per tool call.
 */
export class IpcSession {
  private socket: net.Socket | null = null;
  private buffer = Buffer.alloc(0);
  private nextRequestId = 1;
  private pending = new Map<number, Pending>();
  private connecting: Promise<void> | null = null;
  private helloDone = false;
  private serviceVersion: string | null = null;
  private pushHandlers = new Set<PushHandler>();

  constructor(private readonly pipeName = PIPE_NAME) {}

  get connected(): boolean {
    return this.socket !== null && !this.socket.destroyed && this.helloDone;
  }

  get lastServiceVersion(): string | null {
    return this.serviceVersion;
  }

  onPush(handler: PushHandler): () => void {
    this.pushHandlers.add(handler);
    return () => this.pushHandlers.delete(handler);
  }

  async ensureConnected(timeoutMs = 5000): Promise<void> {
    if (this.connected) return;
    if (this.connecting) return this.connecting;
    this.connecting = this.connectInternal(timeoutMs).finally(() => {
      this.connecting = null;
    });
    return this.connecting;
  }

  async request(body: Body, timeoutMs = 5000): Promise<Envelope> {
    await this.ensureConnected(timeoutMs);
    const socket = this.socket;
    if (!socket || socket.destroyed) {
      throw new PulseIpcError(
        "PulseService pipe not connected",
        "SERVICE_UNAVAILABLE",
      );
    }
    const requestId = this.nextRequestId++;
    const env: Envelope = { requestId, body };
    return new Promise<Envelope>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        reject(
          new PulseIpcError(`IPC timeout waiting for ${body.type}`, "TIMEOUT"),
        );
      }, timeoutMs);
      this.pending.set(requestId, { resolve, reject, timer });
      try {
        socket.write(encodeFrame(encodeEnvelope(env)));
      } catch (err) {
        clearTimeout(timer);
        this.pending.delete(requestId);
        reject(
          new PulseIpcError(
            err instanceof Error ? err.message : String(err),
            "SERVICE_UNAVAILABLE",
          ),
        );
      }
    });
  }

  async close(): Promise<void> {
    this.rejectAll(new PulseIpcError("IPC session closed", "SERVICE_UNAVAILABLE"));
    this.helloDone = false;
    const s = this.socket;
    this.socket = null;
    if (s && !s.destroyed) s.destroy();
  }

  private async connectInternal(timeoutMs: number): Promise<void> {
    if (this.socket && !this.socket.destroyed) {
      this.socket.destroy();
      this.socket = null;
    }
    this.helloDone = false;
    this.buffer = Buffer.alloc(0);

    return new Promise((resolve, reject) => {
      const socket = net.connect(this.pipeName);
      let settled = false;

      const fail = (err: Error) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        this.helloDone = false;
        this.socket = null;
        reject(err);
      };

      const timer = setTimeout(() => {
        fail(
          new PulseIpcError(
            "IPC timeout connecting to PulseService",
            "TIMEOUT",
          ),
        );
        socket.destroy();
      }, timeoutMs);

      socket.on("connect", () => {
        this.socket = socket;
        const helloId = this.nextRequestId++;
        const hello: Envelope = {
          requestId: helloId,
          body: {
            type: "ClientHello",
            protocolVersion: IPC_PROTOCOL_VERSION,
            clientName: CLIENT_NAME,
            clientVersion: MCP_SERVER_VERSION,
          },
        };
        this.pending.set(helloId, {
          resolve: (env) => {
            if (env.body.type !== "ServerHello") {
              fail(
                new PulseIpcError(
                  `expected ServerHello, got ${env.body.type}`,
                  "INTERNAL_ERROR",
                ),
              );
              return;
            }
            this.serviceVersion = env.body.serviceVersion || null;
            this.helloDone = true;
            if (!settled) {
              settled = true;
              clearTimeout(timer);
              resolve();
            }
          },
          reject: (err) => fail(err),
          timer: setTimeout(() => {
            fail(new PulseIpcError("IPC timeout on ServerHello", "TIMEOUT"));
          }, timeoutMs),
        });
        socket.write(encodeFrame(encodeEnvelope(hello)));
      });

      socket.on("data", (chunk: Buffer) => {
        this.buffer = Buffer.concat([this.buffer, chunk]);
        try {
          while (true) {
            const frame = tryDecodeFrame(this.buffer);
            if (!frame) break;
            this.buffer = this.buffer.subarray(frame.consumed);
            const env = decodeEnvelope(frame.payload);
            if (env.requestId === 0) {
              for (const h of this.pushHandlers) h(env);
              continue;
            }
            const p = this.pending.get(env.requestId);
            if (p) {
              clearTimeout(p.timer);
              this.pending.delete(env.requestId);
              p.resolve(env);
            }
          }
        } catch (err) {
          fail(
            err instanceof PulseIpcError
              ? err
              : new PulseIpcError(
                  err instanceof Error ? err.message : String(err),
                  "INTERNAL_ERROR",
                ),
          );
        }
      });

      socket.on("error", (err) => {
        this.rejectAll(new PulseIpcError(err.message, "SERVICE_UNAVAILABLE"));
        fail(new PulseIpcError(err.message, "SERVICE_UNAVAILABLE"));
      });

      socket.on("close", () => {
        const wasConnected = this.helloDone;
        this.helloDone = false;
        this.socket = null;
        this.rejectAll(
          new PulseIpcError("PulseService disconnected", "SERVICE_UNAVAILABLE"),
        );
        if (!settled && wasConnected === false) {
          // connect path may still be pending via error handler
        }
      });
    });
  }

  private rejectAll(err: Error): void {
    for (const [, p] of this.pending) {
      clearTimeout(p.timer);
      p.reject(err);
    }
    this.pending.clear();
  }
}

let sharedSession: IpcSession | null = null;

export function getSharedIpcSession(): IpcSession {
  if (!sharedSession) sharedSession = new IpcSession();
  return sharedSession;
}

export function resetSharedIpcSessionForTests(): void {
  void sharedSession?.close();
  sharedSession = null;
}
