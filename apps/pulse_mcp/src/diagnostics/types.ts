/** Decoded DiagnosticsSnapshot (proto fields 1–55). */

export interface DiagnosticsSnapshot {
  serviceVersion: string;
  protocolVersion: number;
  serviceStartUnixMs: number;
  serviceUptimeMs: number;
  runMode: string;
  ipcListening: boolean;
  liveSubscribed: boolean;
  liveChannel: string;
  liveEventsPushed: number;
  liveEventsDropped: number;
  liveSubscriberReconnects: number;
  lastLiveEventUnixMs: number;
  lastLiveEventTitle: string;
  liveQueueDepth: number;
  liveQueueCapacity: number;
  ipcMessagesReceived: number;
  ipcMessagesSent: number;
  ipcErrors: number;
  connectedClients: number;
  servicePid: number;
  hasCpuPercent: boolean;
  cpuPercent: number;
  workingSetBytes: number;
  threadCount: number;
  handleCount: number;
  stageEventLog: number;
  stageCollector: number;
  stageIntelligence: number;
  stageIpc: number;
  stageDetail: string;
  windowsEdition: string;
  windowsVersion: string;
  executablePath: string;
  buildVersion: string;
  gitCommit: string;
  binarySha256: string;
  installPath: string;
  hasPathsMatch: boolean;
  pathsMatch: boolean;
  scmState: string;
  scmStartupType: string;
  ipcBytesReceived: number;
  ipcBytesSent: number;
  hasIpcMessagesPerSec: boolean;
  ipcMessagesPerSec: number;
  hasIpcBytesPerSec: boolean;
  ipcBytesPerSec: number;
  healthMonitoringActive: boolean;
  healthSampleRateHz: number;
  networkEtwRunning: boolean;
  networkEtwLastError: string;
  stageEventLogDetail: string;
  stageCollectorDetail: string;
  stageIntelligenceDetail: string;
  stageIpcDetail: string;
}

export function emptyDiagnosticsSnapshot(): DiagnosticsSnapshot {
  return {
    serviceVersion: "",
    protocolVersion: 0,
    serviceStartUnixMs: 0,
    serviceUptimeMs: 0,
    runMode: "",
    ipcListening: false,
    liveSubscribed: false,
    liveChannel: "",
    liveEventsPushed: 0,
    liveEventsDropped: 0,
    liveSubscriberReconnects: 0,
    lastLiveEventUnixMs: 0,
    lastLiveEventTitle: "",
    liveQueueDepth: 0,
    liveQueueCapacity: 0,
    ipcMessagesReceived: 0,
    ipcMessagesSent: 0,
    ipcErrors: 0,
    connectedClients: 0,
    servicePid: 0,
    hasCpuPercent: false,
    cpuPercent: 0,
    workingSetBytes: 0,
    threadCount: 0,
    handleCount: 0,
    stageEventLog: 0,
    stageCollector: 0,
    stageIntelligence: 0,
    stageIpc: 0,
    stageDetail: "",
    windowsEdition: "",
    windowsVersion: "",
    executablePath: "",
    buildVersion: "",
    gitCommit: "",
    binarySha256: "",
    installPath: "",
    hasPathsMatch: false,
    pathsMatch: false,
    scmState: "",
    scmStartupType: "",
    ipcBytesReceived: 0,
    ipcBytesSent: 0,
    hasIpcMessagesPerSec: false,
    ipcMessagesPerSec: 0,
    hasIpcBytesPerSec: false,
    ipcBytesPerSec: 0,
    healthMonitoringActive: false,
    healthSampleRateHz: 0,
    networkEtwRunning: false,
    networkEtwLastError: "",
    stageEventLogDetail: "",
    stageCollectorDetail: "",
    stageIntelligenceDetail: "",
    stageIpcDetail: "",
  };
}

export function stageLabel(code: number): "healthy" | "warning" | "error" {
  if (code === 1) return "warning";
  if (code === 2) return "error";
  return "healthy";
}
