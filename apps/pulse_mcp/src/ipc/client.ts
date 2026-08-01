import net from "node:net";

import { encodeFrame, tryDecodeFrame } from "./framing.js";
import {
  decodeEnvelope,
  encodeEnvelope,
  type Envelope,
  type Pong,
  type ServerHello,
} from "./wire.js";
import {
  CLIENT_NAME,
  IPC_PROTOCOL_VERSION,
  MCP_SERVER_VERSION,
  PIPE_NAME,
} from "../version.js";

export class PulseIpcError extends Error {
  constructor(
    message: string,
    readonly code: "SERVICE_UNAVAILABLE" | "TIMEOUT" | "INTERNAL",
  ) {
    super(message);
    this.name = "PulseIpcError";
  }
}

export interface IpcHelloResult {
  connected: boolean;
  serviceVersion: string | null;
  ipcProtocolVersion: number;
  error?: string;
}

/**
 * Short-lived named-pipe client: ClientHello → ServerHello, Ping → Pong.
 * Suitable for M1 health / mcp.self; later milestones may keep a session open.
 */
export async function ipcHello(opts?: {
  pipeName?: string;
  timeoutMs?: number;
}): Promise<IpcHelloResult> {
  const pipeName = opts?.pipeName ?? PIPE_NAME;
  const timeoutMs = opts?.timeoutMs ?? 3000;

  return new Promise((resolve) => {
    const socket = net.connect(pipeName);
    let buffer = Buffer.alloc(0);
    let settled = false;
    let phase: "hello" | "pong" = "hello";
    let serviceVersion: string | null = null;

    const finish = (result: IpcHelloResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.destroy();
      resolve(result);
    };

    const timer = setTimeout(() => {
      finish({
        connected: false,
        serviceVersion: null,
        ipcProtocolVersion: IPC_PROTOCOL_VERSION,
        error: "IPC timeout waiting for PulseService",
      });
    }, timeoutMs);

    const send = (env: Envelope) => {
      const payload = encodeEnvelope(env);
      socket.write(encodeFrame(payload));
    };

    socket.on("connect", () => {
      send({
        requestId: 1,
        body: {
          type: "ClientHello",
          protocolVersion: IPC_PROTOCOL_VERSION,
          clientName: CLIENT_NAME,
          clientVersion: MCP_SERVER_VERSION,
        },
      });
    });

    socket.on("data", (chunk: Buffer) => {
      buffer = Buffer.concat([buffer, chunk]);
      try {
        while (true) {
          const frame = tryDecodeFrame(buffer);
          if (!frame) break;
          buffer = buffer.subarray(frame.consumed);
          const env = decodeEnvelope(frame.payload);
          if (phase === "hello") {
            if (env.body.type !== "ServerHello") {
              finish({
                connected: false,
                serviceVersion: null,
                ipcProtocolVersion: IPC_PROTOCOL_VERSION,
                error: `expected ServerHello, got ${env.body.type}`,
              });
              return;
            }
            const hello = env.body as ServerHello;
            serviceVersion = hello.serviceVersion || null;
            phase = "pong";
            send({
              requestId: 2,
              body: {
                type: "Ping",
                nonce: 42,
                unixMs: Date.now(),
              },
            });
          } else {
            if (env.body.type !== "Pong") {
              finish({
                connected: false,
                serviceVersion,
                ipcProtocolVersion: IPC_PROTOCOL_VERSION,
                error: `expected Pong, got ${env.body.type}`,
              });
              return;
            }
            const pong = env.body as Pong;
            if (pong.serviceVersion) serviceVersion = pong.serviceVersion;
            finish({
              connected: true,
              serviceVersion,
              ipcProtocolVersion: IPC_PROTOCOL_VERSION,
            });
            return;
          }
        }
      } catch (err) {
        finish({
          connected: false,
          serviceVersion,
          ipcProtocolVersion: IPC_PROTOCOL_VERSION,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    });

    socket.on("error", (err) => {
      finish({
        connected: false,
        serviceVersion: null,
        ipcProtocolVersion: IPC_PROTOCOL_VERSION,
        error: err.message,
      });
    });
  });
}
