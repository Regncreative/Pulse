import { stageLabel, type DiagnosticsSnapshot } from "./types.js";

function isoFromUnixMs(ms: number): string | null {
  if (!ms || ms <= 0) return null;
  return new Date(ms).toISOString();
}

/** Stable observedAt from service clock when available (ISO-8601 UTC). */
function diagnosticsObservedAt(snap: DiagnosticsSnapshot): string {
  if (snap.serviceStartUnixMs > 0 && snap.serviceUptimeMs >= 0) {
    return new Date(snap.serviceStartUnixMs + snap.serviceUptimeMs).toISOString();
  }
  return new Date().toISOString();
}

export function mapDiagnosticsSnapshot(
  snap: DiagnosticsSnapshot,
): Record<string, unknown> {
  const observedAt = diagnosticsObservedAt(snap);
  return {
    observedAt,
    service: {
      version: snap.serviceVersion || null,
      buildVersion: snap.buildVersion || null,
      protocolVersion: snap.protocolVersion || null,
      runMode: snap.runMode || null,
      pid: snap.servicePid || null,
      startedAt: isoFromUnixMs(snap.serviceStartUnixMs),
      uptimeMs: snap.serviceUptimeMs,
      executablePath: snap.executablePath || null,
      installPath: snap.installPath || null,
      gitCommit: snap.gitCommit || null,
      binarySha256: snap.binarySha256 || null,
      pathsMatch: snap.hasPathsMatch ? snap.pathsMatch : null,
      scmState: snap.scmState || null,
      scmStartupType: snap.scmStartupType || null,
      ipcListening: snap.ipcListening,
      connectedClients: snap.connectedClients,
    },
    windows: {
      edition: snap.windowsEdition || null,
      version: snap.windowsVersion || null,
    },
    live: {
      subscribed: snap.liveSubscribed,
      channel: snap.liveChannel || null,
      eventsPushed: snap.liveEventsPushed,
      eventsDropped: snap.liveEventsDropped,
      subscriberReconnects: snap.liveSubscriberReconnects,
      lastEventAt: isoFromUnixMs(snap.lastLiveEventUnixMs),
      lastEventTitle: snap.lastLiveEventTitle || null,
      queueDepth: snap.liveQueueDepth,
      queueCapacity: snap.liveQueueCapacity,
    },
    ipc: {
      messagesReceived: snap.ipcMessagesReceived,
      messagesSent: snap.ipcMessagesSent,
      errors: snap.ipcErrors,
      bytesReceived: snap.ipcBytesReceived,
      bytesSent: snap.ipcBytesSent,
      messagesPerSec: snap.hasIpcMessagesPerSec
        ? snap.ipcMessagesPerSec
        : null,
      bytesPerSec: snap.hasIpcBytesPerSec ? snap.ipcBytesPerSec : null,
    },
    pipeline: {
      eventLog: {
        state: stageLabel(snap.stageEventLog),
        detail: snap.stageEventLogDetail || snap.stageDetail || null,
      },
      collector: {
        state: stageLabel(snap.stageCollector),
        detail: snap.stageCollectorDetail || null,
      },
      intelligence: {
        state: stageLabel(snap.stageIntelligence),
        detail: snap.stageIntelligenceDetail || null,
      },
      ipc: {
        state: stageLabel(snap.stageIpc),
        detail: snap.stageIpcDetail || null,
      },
    },
    collectors: {
      healthMonitoringActive: snap.healthMonitoringActive,
      healthSampleRateHz: snap.healthSampleRateHz,
      networkEtwRunning: snap.networkEtwRunning,
      networkEtwLastError: snap.networkEtwLastError || null,
    },
    performance: {
      cpuPercent: snap.hasCpuPercent ? snap.cpuPercent : null,
      workingSetBytes: snap.workingSetBytes,
      threadCount: snap.threadCount,
      handleCount: snap.handleCount,
    },
  };
}

/** Doc 33 §10.11 — PulseService only; catalog remains Inventory. */
export function mapServiceStatus(
  snap: DiagnosticsSnapshot,
): Record<string, unknown> {
  const scm = (snap.scmState || "").toLowerCase();
  const installed =
    scm !== "notinstalled" &&
    scm !== "not installed" &&
    (Boolean(snap.installPath) ||
      Boolean(snap.executablePath) ||
      scm.length > 0);
  const running = scm === "running" || scm === "start_pending";

  return {
    observedAt: new Date().toISOString(),
    pulseService: {
      installed,
      running,
      startType: snap.scmStartupType || null,
      version: snap.serviceVersion || snap.buildVersion || null,
      path: snap.executablePath || snap.installPath || null,
      account: null,
      scmState: snap.scmState || null,
      runMode: snap.runMode || null,
      pid: snap.servicePid || null,
      unavailable: {
        account:
          "Service account is not collected on the diagnostics wire in this milestone",
      },
    },
    catalog: {
      available: false,
      reason:
        "Full Windows service inventory is not collected in this Pulse milestone. Use Inventory tools when enabled.",
    },
  };
}
