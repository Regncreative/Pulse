import type { DiagnosticsCache } from "../diagnostics/cache.js";
import { mapDiagnosticsSnapshot } from "../diagnostics/mappers.js";
import type { HealthCache } from "../health/cache.js";
import { mapHealth } from "../health/mappers.js";
import type { IpcSession } from "../ipc/session.js";
import type { TimelineCache } from "../timeline/cache.js";
import { mapTimelineEvent } from "../timeline/mappers.js";
import {
  filterTimelineEvents,
  type TimelineSearchFilters,
} from "../timeline/query.js";
import {
  fetchInventoryDomain,
  INVENTORY_DOMAIN_PCI,
  INVENTORY_DOMAIN_USB,
} from "./inventory.js";
import type { ReportFilters, ReportType } from "./types.js";

export interface GatheredReportData {
  health: Record<string, unknown> | null;
  diagnostics: Record<string, unknown> | null;
  events: Record<string, unknown>[];
  usb: Awaited<ReturnType<typeof fetchInventoryDomain>> | null;
  pci: Awaited<ReturnType<typeof fetchInventoryDomain>> | null;
  identity: Record<string, string>;
}

export interface GatherDeps {
  session: IpcSession;
  health: HealthCache;
  timeline: TimelineCache;
  diagnostics: DiagnosticsCache;
}

export async function gatherReportData(
  deps: GatherDeps,
  template: ReportType,
  filters: ReportFilters = {},
): Promise<GatheredReportData> {
  const needHealth =
    template === "health" ||
    template === "hardware" ||
    template === "combined" ||
    template === "diagnostics";
  const needDiag = template === "diagnostics" || template === "combined";
  const needTimeline = template === "timeline" || template === "combined";
  const needInventory = template === "hardware";

  const healthSnap = needHealth
    ? await deps.health.ensureSnapshot(true)
    : null;
  const health = healthSnap ? mapHealth(healthSnap) : null;

  const diagnostics = needDiag
    ? mapDiagnosticsSnapshot(await deps.diagnostics.ensureSnapshot(true))
    : null;

  let events: Record<string, unknown>[] = [];
  if (needTimeline) {
    const limit = Math.min(Math.max(filters.limit ?? 200, 1), 500);
    const channelIpc =
      filters.channel === "security"
        ? "Security"
        : filters.channel === "application"
          ? "Application"
          : filters.channel === "other"
            ? "Other"
            : "System";
    const snap = await deps.timeline.getSnapshot({
      limit,
      channel: channelIpc,
    });
    const q: TimelineSearchFilters = {
      limit,
      channel: filters.channel,
      keyword: filters.keyword,
      from: filters.from,
      to: filters.to,
      severity: filters.severity as TimelineSearchFilters["severity"],
    };
    const filtered = filterTimelineEvents(snap.events, q).slice(0, limit);
    events = filtered.map((e) => mapTimelineEvent(e));
  }

  let usb = null;
  let pci = null;
  if (needInventory) {
    const invLimit = Math.min(Math.max(filters.limit ?? 500, 1), 2000);
    [usb, pci] = await Promise.all([
      fetchInventoryDomain(deps.session, INVENTORY_DOMAIN_USB, invLimit),
      fetchInventoryDomain(deps.session, INVENTORY_DOMAIN_PCI, invLimit),
    ]);
  }

  const identity: Record<string, string> = {};
  if (healthSnap) {
    const info = healthSnap.info;
    const windows =
      `${info.windowsEdition} ${info.windowsVersion}`.trim() || "—";
    identity.windows = windows;
    if (info.cpuModel) identity.cpu = info.cpuModel;
    if (info.gpuModel) identity.gpu = info.gpuModel;
  } else if (diagnostics) {
    const win = diagnostics.windows as {
      edition?: string | null;
      version?: string | null;
    };
    identity.windows =
      `${win?.edition ?? ""} ${win?.version ?? ""}`.trim() || "—";
  }

  return { health, diagnostics, events, usb, pci, identity };
}
