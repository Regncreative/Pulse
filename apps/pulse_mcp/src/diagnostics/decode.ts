import { Reader } from "../ipc/pb.js";
import { emptyDiagnosticsSnapshot, type DiagnosticsSnapshot } from "./types.js";

export function decodeDiagnosticsSnapshot(
  data: Uint8Array,
): DiagnosticsSnapshot {
  const r = new Reader(data);
  const m = emptyDiagnosticsSnapshot();
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    const setBool = () => r.readVarint() !== 0;
    const setU64 = () => Number(r.readVarintBig());
    if (field === 1 && wire === 2) m.serviceVersion = r.readString();
    else if (field === 2 && wire === 0) m.protocolVersion = r.readVarint();
    else if (field === 3 && wire === 0) m.serviceStartUnixMs = setU64();
    else if (field === 4 && wire === 0) m.serviceUptimeMs = setU64();
    else if (field === 5 && wire === 2) m.runMode = r.readString();
    else if (field === 6 && wire === 0) m.ipcListening = setBool();
    else if (field === 7 && wire === 0) m.liveSubscribed = setBool();
    else if (field === 8 && wire === 2) m.liveChannel = r.readString();
    else if (field === 9 && wire === 0) m.liveEventsPushed = setU64();
    else if (field === 10 && wire === 0) m.liveEventsDropped = setU64();
    else if (field === 11 && wire === 0) m.liveSubscriberReconnects = setU64();
    else if (field === 12 && wire === 0) m.lastLiveEventUnixMs = setU64();
    else if (field === 13 && wire === 2) m.lastLiveEventTitle = r.readString();
    else if (field === 14 && wire === 0) m.liveQueueDepth = r.readVarint();
    else if (field === 15 && wire === 0) m.liveQueueCapacity = r.readVarint();
    else if (field === 16 && wire === 0) m.ipcMessagesReceived = setU64();
    else if (field === 17 && wire === 0) m.ipcMessagesSent = setU64();
    else if (field === 18 && wire === 0) m.ipcErrors = setU64();
    else if (field === 19 && wire === 0) m.connectedClients = r.readVarint();
    else if (field === 20 && wire === 0) m.servicePid = r.readVarint();
    else if (field === 21 && wire === 0) m.hasCpuPercent = setBool();
    else if (field === 22 && wire === 1) m.cpuPercent = r.readDouble();
    else if (field === 23 && wire === 0) m.workingSetBytes = setU64();
    else if (field === 24 && wire === 0) m.threadCount = r.readVarint();
    else if (field === 25 && wire === 0) m.handleCount = r.readVarint();
    else if (field === 26 && wire === 0) m.stageEventLog = r.readVarint();
    else if (field === 27 && wire === 0) m.stageCollector = r.readVarint();
    else if (field === 28 && wire === 0) m.stageIntelligence = r.readVarint();
    else if (field === 29 && wire === 0) m.stageIpc = r.readVarint();
    else if (field === 30 && wire === 2) m.stageDetail = r.readString();
    else if (field === 31 && wire === 2) m.windowsEdition = r.readString();
    else if (field === 32 && wire === 2) m.windowsVersion = r.readString();
    else if (field === 33 && wire === 2) m.executablePath = r.readString();
    else if (field === 34 && wire === 2) m.buildVersion = r.readString();
    else if (field === 35 && wire === 2) m.gitCommit = r.readString();
    else if (field === 36 && wire === 2) m.binarySha256 = r.readString();
    else if (field === 37 && wire === 2) m.installPath = r.readString();
    else if (field === 38 && wire === 0) m.hasPathsMatch = setBool();
    else if (field === 39 && wire === 0) m.pathsMatch = setBool();
    else if (field === 40 && wire === 2) m.scmState = r.readString();
    else if (field === 41 && wire === 2) m.scmStartupType = r.readString();
    else if (field === 42 && wire === 0) m.ipcBytesReceived = setU64();
    else if (field === 43 && wire === 0) m.ipcBytesSent = setU64();
    else if (field === 44 && wire === 0) m.hasIpcMessagesPerSec = setBool();
    else if (field === 45 && wire === 1) m.ipcMessagesPerSec = r.readDouble();
    else if (field === 46 && wire === 0) m.hasIpcBytesPerSec = setBool();
    else if (field === 47 && wire === 1) m.ipcBytesPerSec = r.readDouble();
    else if (field === 48 && wire === 0) m.healthMonitoringActive = setBool();
    else if (field === 49 && wire === 1) m.healthSampleRateHz = r.readDouble();
    else if (field === 50 && wire === 0) m.networkEtwRunning = setBool();
    else if (field === 51 && wire === 2) m.networkEtwLastError = r.readString();
    else if (field === 52 && wire === 2) m.stageEventLogDetail = r.readString();
    else if (field === 53 && wire === 2) m.stageCollectorDetail = r.readString();
    else if (field === 54 && wire === 2)
      m.stageIntelligenceDetail = r.readString();
    else if (field === 55 && wire === 2) m.stageIpcDetail = r.readString();
    else r.skip(wire);
  }
  return m;
}
