import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  SubscribeRequestSchema,
  UnsubscribeRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

import {
  V1_RESOURCES,
  V1_SUBSCRIPTIONS,
  V1_TOOLS,
  V1_TOOL_NAMESPACES,
} from "../catalog/v1.js";
import type { HealthCache } from "../health/cache.js";
import {
  mapCpu,
  mapGpu,
  mapHealth,
  mapMemory,
  mapNetwork,
  mapStorage,
} from "../health/mappers.js";
import type { PulseMcpLogger } from "../logging/logger.js";
import type { MetricsRegistry } from "../metrics/metrics.js";
import type { McpPolicy } from "../policy/policy.js";
import type { IpcSession } from "../ipc/session.js";
import {
  filterSortProcesses,
  mapProcessDetails,
} from "../process/mappers.js";
import { runMcpSelf } from "../tools/mcp/self.js";
import { runObservationTool, type ToolRuntime } from "../tools/runTool.js";
import { MCP_SERVER_VERSION } from "../version.js";
import { PulseIpcError } from "../ipc/session.js";

export interface CreateServerOptions {
  metrics: MetricsRegistry;
  policy: McpPolicy;
  logger: PulseMcpLogger;
  session: IpcSession;
  health: HealthCache;
}

const SYSTEM_RESOURCE_META: Record<
  string,
  { name: string; description: string }
> = {
  "pulse://system/cpu": {
    name: "CPU",
    description: "Latest CPU sample from Pulse Health Engine (~1 Hz when subscribed).",
  },
  "pulse://system/memory": {
    name: "Memory",
    description: "Latest memory sample from Pulse Health Engine.",
  },
  "pulse://system/gpu": {
    name: "GPU",
    description: "Latest GPU sample from Pulse Health Engine (primary adapter).",
  },
  "pulse://system/network": {
    name: "Network",
    description: "Latest network sample from Pulse Health Engine.",
  },
  "pulse://system/health": {
    name: "Health",
    description: "Full health snapshot (static + sample) from Pulse Health Engine.",
  },
};

export function createPulseMcpServer(opts: CreateServerOptions): McpServer {
  const runtime: ToolRuntime = {
    metrics: opts.metrics,
    policy: opts.policy,
    logger: opts.logger,
    session: opts.session,
    health: opts.health,
  };

  const server = new McpServer(
    {
      name: "pulse",
      version: MCP_SERVER_VERSION,
    },
    {
      capabilities: {
        resources: {
          subscribe: true,
          listChanged: true,
        },
      },
    },
  );

  const subscribed = new Set<string>();
  let lastPublishedJson = new Map<string, string>();

  const publishIfChanged = async (uri: string, payload: unknown) => {
    const json = JSON.stringify(payload);
    if (lastPublishedJson.get(uri) === json) return;
    lastPublishedJson.set(uri, json);
    try {
      await server.server.sendResourceUpdated({ uri });
    } catch {
      // Client may have disconnected.
    }
  };

  const onHealthSample = () => {
    void (async () => {
      if (subscribed.size === 0) return;
      try {
        const snap = await opts.health.ensureSnapshot();
        if (subscribed.has("pulse://system/cpu")) {
          await publishIfChanged(
            "pulse://system/cpu",
            mapCpu(snap.sample, snap.info),
          );
        }
        if (subscribed.has("pulse://system/memory")) {
          await publishIfChanged(
            "pulse://system/memory",
            mapMemory(snap.sample, snap.info),
          );
        }
        if (subscribed.has("pulse://system/gpu")) {
          await publishIfChanged(
            "pulse://system/gpu",
            mapGpu(snap.sample, snap.info),
          );
        }
        if (subscribed.has("pulse://system/network")) {
          await publishIfChanged(
            "pulse://system/network",
            mapNetwork(snap.sample, snap.info),
          );
        }
        if (subscribed.has("pulse://system/health")) {
          await publishIfChanged("pulse://system/health", mapHealth(snap));
        }
      } catch (err) {
        opts.logger.warn("resource.publish_fail", {
          error: err instanceof Error ? err.message : String(err),
        });
      }
    })();
  };

  opts.health.onSample(onHealthSample);

  server.registerTool(
    "mcp.self",
    {
      title: "PulseMCP self diagnostics",
      description:
        "Returns PulseMCP versions (MCP protocol, server, Pulse app, PulseService, IPC), tool namespaces, capability discovery, connection health, and local diagnostics. Observation only. Structured JSON only.",
      inputSchema: z.object({}),
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async () =>
      runMcpSelf({
        metrics: opts.metrics,
        policy: opts.policy,
        logPath: opts.logger.logPath,
        transport: "stdio",
        session: opts.session,
        activeSubscriptions: [...subscribed],
      }),
  );

  const systemTool = (
    name: (typeof V1_TOOLS)[number],
    title: string,
    description: string,
    inputSchema: z.ZodTypeAny,
    handler: (args: Record<string, unknown>) => Promise<unknown>,
  ) => {
    server.registerTool(
      name,
      {
        title,
        description,
        inputSchema,
        annotations: {
          readOnlyHint: true,
          destructiveHint: false,
          idempotentHint: true,
          openWorldHint: false,
        },
      },
      async (args) =>
        runObservationTool(runtime, name, () =>
          handler((args ?? {}) as Record<string, unknown>),
        ),
    );
  };

  systemTool(
    "system.health",
    "System health snapshot",
    "Full or sectioned health snapshot from Pulse Health Engine (GetHealthSnapshot / cached HealthUpdate). Null when unsupported. Structured JSON only.",
    z.object({
      sections: z
        .array(
          z.enum(["cpu", "memory", "gpu", "storage", "network", "static"]),
        )
        .optional(),
      forceRefresh: z.boolean().optional(),
    }),
    async (args) => {
      const snap = await opts.health.ensureSnapshot(
        args.forceRefresh === true,
      );
      return mapHealth(snap, args.sections as string[] | undefined);
    },
  );

  systemTool(
    "system.cpu",
    "CPU metrics",
    "Latest CPU utilization and topology from Pulse Health Engine cache/snapshot. Structured JSON only.",
    z.object({ forceRefresh: z.boolean().optional() }),
    async (args) => {
      const snap = await opts.health.ensureSnapshot(
        args.forceRefresh === true,
      );
      return mapCpu(snap.sample, snap.info);
    },
  );

  systemTool(
    "system.memory",
    "Memory metrics",
    "Latest memory metrics from Pulse Health Engine. Structured JSON only.",
    z.object({ forceRefresh: z.boolean().optional() }),
    async (args) => {
      const snap = await opts.health.ensureSnapshot(
        args.forceRefresh === true,
      );
      return mapMemory(snap.sample, snap.info);
    },
  );

  systemTool(
    "system.gpu",
    "GPU metrics",
    "Latest GPU metrics for the primary adapter from Pulse Health Engine. Structured JSON only.",
    z.object({ forceRefresh: z.boolean().optional() }),
    async (args) => {
      const snap = await opts.health.ensureSnapshot(
        args.forceRefresh === true,
      );
      return mapGpu(snap.sample, snap.info);
    },
  );

  systemTool(
    "system.storage",
    "Storage metrics",
    "Volumes, physical disk throughput, and storage summary from Pulse Health Engine. Structured JSON only.",
    z.object({ forceRefresh: z.boolean().optional() }),
    async (args) => {
      const snap = await opts.health.ensureSnapshot(
        args.forceRefresh === true,
      );
      return mapStorage(snap.sample, snap.info);
    },
  );

  systemTool(
    "system.network",
    "Network metrics",
    "Latest network rates and addressing from Pulse Health Engine. Structured JSON only.",
    z.object({ forceRefresh: z.boolean().optional() }),
    async (args) => {
      const snap = await opts.health.ensureSnapshot(
        args.forceRefresh === true,
      );
      return mapNetwork(snap.sample, snap.info);
    },
  );

  const processFilterSchema = z.object({
    cpuAbove: z.number().optional(),
    memoryAboveBytes: z.number().optional(),
    company: z.string().optional(),
    signed: z.boolean().optional(),
    running: z.boolean().optional(),
    applicationOnly: z.boolean().optional(),
    backgroundOnly: z.boolean().optional(),
    systemOnly: z.boolean().optional(),
    nameContains: z.string().optional(),
    limit: z.number().int().min(1).max(500).optional(),
    offset: z.number().int().min(0).optional(),
    sortBy: z.enum(["cpu", "memory", "name", "pid"]).optional(),
    sortDir: z.enum(["asc", "desc"]).optional(),
  });

  systemTool(
    "process.list",
    "Process inventory",
    "Filtered process inventory from Pulse Health Engine process stream. Structured JSON only.",
    processFilterSchema,
    async (args) => {
      return opts.health.withInventory(async () => {
        const observedAt = new Date().toISOString();
        const result = filterSortProcesses(
          opts.health.listProcesses(),
          args as Parameters<typeof filterSortProcesses>[1],
        );
        return {
          observedAt,
          ...result,
        };
      });
    },
  );

  systemTool(
    "process.search",
    "Process search",
    "Search process inventory by name/path (required query). Same filters as process.list. Structured JSON only.",
    processFilterSchema.extend({
      query: z.string().min(1),
    }),
    async (args) => {
      const query = String((args as { query?: string }).query ?? "").trim();
      if (!query) {
        throw new PulseIpcError("query is required", "INVALID_ARGUMENT");
      }
      return opts.health.withInventory(async () => {
        const observedAt = new Date().toISOString();
        const result = filterSortProcesses(opts.health.listProcesses(), {
          ...(args as Parameters<typeof filterSortProcesses>[1]),
          query,
        });
        return {
          observedAt,
          query,
          ...result,
        };
      });
    },
  );

  systemTool(
    "process.details",
    "Process details",
    "Detailed process metadata via GetProcessDetails (cmdline redacted). Structured JSON only.",
    z.object({
      pid: z.number().int().positive(),
    }),
    async (args) => {
      const pid = Number((args as { pid: number }).pid);
      if (!Number.isInteger(pid) || pid <= 0) {
        throw new PulseIpcError(
          "pid must be a positive integer",
          "INVALID_ARGUMENT",
        );
      }
      return opts.health.withInventory(async () => {
        const details = await opts.health.getProcessDetails(pid);
        const live = opts.health.getProcess(pid);
        const mapped = mapProcessDetails(details, live);
        return {
          observedAt: new Date().toISOString(),
          ...mapped,
        };
      });
    },
  );

  for (const uri of V1_RESOURCES) {
    const meta = SYSTEM_RESOURCE_META[uri]!;
    server.registerResource(
      meta.name,
      uri,
      {
        description: meta.description,
        mimeType: "application/json",
      },
      async () => {
        if (!opts.policy.enabled) {
          return {
            contents: [
              {
                uri,
                mimeType: "application/json",
                text: JSON.stringify({
                  ok: false,
                  code: "POLICY_DISABLED",
                  message: "Pulse MCP bridge is disabled",
                }),
              },
            ],
          };
        }
        const snap = await opts.health.ensureSnapshot();
        let payload: unknown;
        switch (uri) {
          case "pulse://system/cpu":
            payload = mapCpu(snap.sample, snap.info);
            break;
          case "pulse://system/memory":
            payload = mapMemory(snap.sample, snap.info);
            break;
          case "pulse://system/gpu":
            payload = mapGpu(snap.sample, snap.info);
            break;
          case "pulse://system/network":
            payload = mapNetwork(snap.sample, snap.info);
            break;
          default:
            payload = mapHealth(snap);
        }
        return {
          contents: [
            {
              uri,
              mimeType: "application/json",
              text: JSON.stringify(payload),
            },
          ],
        };
      },
    );
  }

  server.server.setRequestHandler(SubscribeRequestSchema, async (request) => {
    const uri = request.params.uri;
    if (!(V1_SUBSCRIPTIONS as readonly string[]).includes(uri)) {
      throw new Error(`NOT_SUPPORTED: resource ${uri}`);
    }
    if (!opts.policy.enabled) {
      throw new Error("POLICY_DISABLED");
    }
    const firstSubscriber = subscribed.size === 0;
    subscribed.add(uri);
    if (firstSubscriber) {
      // Start HealthUpdate stream only while ≥1 MCP resource is subscribed.
      await opts.health.addSubscriber();
    }
    opts.logger.info("resource.subscribe", { uri, count: subscribed.size });
    lastPublishedJson.delete(uri);
    onHealthSample();
    return {};
  });

  server.server.setRequestHandler(UnsubscribeRequestSchema, async (request) => {
    const uri = request.params.uri;
    if (subscribed.delete(uri) && subscribed.size === 0) {
      lastPublishedJson.clear();
      await opts.health.removeSubscriber();
    }
    opts.logger.info("resource.unsubscribe", { uri, count: subscribed.size });
    return {};
  });

  void V1_TOOL_NAMESPACES;
  return server;
}
