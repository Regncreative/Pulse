import { Reader } from "../ipc/pb.js";
import {
  emptyProcessDetails,
  emptyProcessEntry,
  emptySample,
  emptyStaticInfo,
  type HealthPhysicalDisk,
  type HealthProcessEntry,
  type HealthProcessInventoryUpdate,
  type HealthSample,
  type HealthSnapshot,
  type HealthStaticInfo,
  type HealthUpdateDecoded,
  type HealthVolume,
  type ProcessDetails,
} from "./types.js";

function decodeVolume(data: Uint8Array): HealthVolume {
  const r = new Reader(data);
  const m: HealthVolume = {
    id: "",
    mountPoint: "",
    label: "",
    fileSystem: "",
    kind: 0,
    usedBytes: 0,
    totalBytes: 0,
    hasCapacity: false,
    includedInSummary: false,
  };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 2) m.id = r.readString();
    else if (field === 2 && wire === 2) m.mountPoint = r.readString();
    else if (field === 3 && wire === 2) m.label = r.readString();
    else if (field === 4 && wire === 2) m.fileSystem = r.readString();
    else if (field === 5 && wire === 0) m.kind = r.readVarint();
    else if (field === 6 && wire === 0) m.usedBytes = Number(r.readVarintBig());
    else if (field === 7 && wire === 0) m.totalBytes = Number(r.readVarintBig());
    else if (field === 8 && wire === 0) m.hasCapacity = r.readVarint() !== 0;
    else if (field === 9 && wire === 0)
      m.includedInSummary = r.readVarint() !== 0;
    else r.skip(wire);
  }
  return m;
}

function decodeDisk(data: Uint8Array): HealthPhysicalDisk {
  const r = new Reader(data);
  const m: HealthPhysicalDisk = {
    id: "",
    name: "",
    hasReadBps: false,
    readBps: 0,
    hasWriteBps: false,
    writeBps: 0,
  };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 2) m.id = r.readString();
    else if (field === 2 && wire === 2) m.name = r.readString();
    else if (field === 3 && wire === 0) m.hasReadBps = r.readVarint() !== 0;
    else if (field === 4 && wire === 1) m.readBps = r.readDouble();
    else if (field === 5 && wire === 0) m.hasWriteBps = r.readVarint() !== 0;
    else if (field === 6 && wire === 1) m.writeBps = r.readDouble();
    else r.skip(wire);
  }
  return m;
}

export function decodeHealthStaticInfo(data: Uint8Array): HealthStaticInfo {
  const r = new Reader(data);
  const m = emptyStaticInfo();
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 2) m.windowsEdition = r.readString();
    else if (field === 2 && wire === 2) m.windowsVersion = r.readString();
    else if (field === 3 && wire === 2) m.cpuModel = r.readString();
    else if (field === 4 && wire === 2) m.gpuModel = r.readString();
    else if (field === 5 && wire === 0)
      m.installedRamBytes = Number(r.readVarintBig());
    else if (field === 6 && wire === 0)
      m.primaryStorageBytes = Number(r.readVarintBig());
    else if (field === 7 && wire === 2) m.activeNetworkAdapter = r.readString();
    else if (field === 8 && wire === 0) m.cpuBaseMhz = r.readVarint();
    else if (field === 9 && wire === 0) m.cpuSockets = r.readVarint();
    else if (field === 10 && wire === 0) m.cpuCores = r.readVarint();
    else if (field === 11 && wire === 0) m.cpuLogicalProcessors = r.readVarint();
    else if (field === 13 && wire === 0)
      m.gpuDedicatedBytes = Number(r.readVarintBig());
    else if (field === 14 && wire === 0)
      m.gpuSharedBytes = Number(r.readVarintBig());
    else if (field === 15 && wire === 2) m.cpuArchitecture = r.readString();
    else if (field === 28 && wire === 2) m.gpuDriverVersion = r.readString();
    else r.skip(wire);
  }
  return m;
}

export function decodeHealthSample(data: Uint8Array): HealthSample {
  const r = new Reader(data);
  const m = emptySample();
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    const setBool = () => r.readVarint() !== 0;
    const setU64 = () => Number(r.readVarintBig());
    if (field === 1 && wire === 0) m.unixMs = setU64();
    else if (field === 2 && wire === 0) m.hasCpuPercent = setBool();
    else if (field === 3 && wire === 1) m.cpuPercent = r.readDouble();
    else if (field === 4 && wire === 0) m.memoryUsedBytes = setU64();
    else if (field === 5 && wire === 0) m.memoryTotalBytes = setU64();
    else if (field === 6 && wire === 0) m.hasGpuPercent = setBool();
    else if (field === 7 && wire === 1) m.gpuPercent = r.readDouble();
    else if (field === 8 && wire === 0) m.hasNetDownloadBps = setBool();
    else if (field === 9 && wire === 1) m.netDownloadBps = r.readDouble();
    else if (field === 10 && wire === 0) m.hasNetUploadBps = setBool();
    else if (field === 11 && wire === 1) m.netUploadBps = r.readDouble();
    else if (field === 12 && wire === 0) m.hasDiskReadBps = setBool();
    else if (field === 13 && wire === 1) m.diskReadBps = r.readDouble();
    else if (field === 14 && wire === 0) m.hasDiskWriteBps = setBool();
    else if (field === 15 && wire === 1) m.diskWriteBps = r.readDouble();
    else if (field === 16 && wire === 0) m.diskUsedBytes = setU64();
    else if (field === 17 && wire === 0) m.diskTotalBytes = setU64();
    else if (field === 18 && wire === 0) m.uptimeMs = setU64();
    else if (field === 19 && wire === 0) m.hasCpuTempC = setBool();
    else if (field === 20 && wire === 1) m.cpuTempC = r.readDouble();
    else if (field === 21 && wire === 0) m.hasGpuTempC = setBool();
    else if (field === 22 && wire === 1) m.gpuTempC = r.readDouble();
    else if (field === 23 && wire === 0) m.hasSsdTempC = setBool();
    else if (field === 24 && wire === 1) m.ssdTempC = r.readDouble();
    else if (field === 25 && wire === 0) m.hasCpuCurrentMhz = setBool();
    else if (field === 26 && wire === 1) m.cpuCurrentMhz = r.readDouble();
    else if (field === 27 && wire === 0) m.memoryAvailableBytes = setU64();
    else if (field === 28 && wire === 0) m.hasMemoryCommitted = setBool();
    else if (field === 29 && wire === 0) m.memoryCommittedBytes = setU64();
    else if (field === 30 && wire === 0) m.memoryCommitLimitBytes = setU64();
    else if (field === 33 && wire === 2) m.ipv4 = r.readString();
    else if (field === 34 && wire === 2) m.ipv6 = r.readString();
    else if (field === 35 && wire === 2) m.gateway = r.readString();
    else if (field === 36 && wire === 2) m.dns = r.readString();
    else if (field === 42 && wire === 1) m.cpuCorePercent.push(r.readDouble());
    else if (field === 43 && wire === 2) m.volumes.push(decodeVolume(r.readBytes()));
    else if (field === 44 && wire === 2) m.disks.push(decodeDisk(r.readBytes()));
    else if (field === 45 && wire === 0) m.hasMemoryCompressed = setBool();
    else if (field === 46 && wire === 0) m.memoryCompressedBytes = setU64();
    else if (field === 49 && wire === 0) m.hasMemoryPagedPool = setBool();
    else if (field === 50 && wire === 0) m.memoryPagedPoolBytes = setU64();
    else if (field === 51 && wire === 0) m.hasMemoryNonpagedPool = setBool();
    else if (field === 52 && wire === 0) m.memoryNonpagedPoolBytes = setU64();
    else if (field === 55 && wire === 0) m.hasGpuUtil3d = setBool();
    else if (field === 56 && wire === 1) m.gpuUtil3d = r.readDouble();
    else if (field === 57 && wire === 0) m.hasGpuUtilCompute = setBool();
    else if (field === 58 && wire === 1) m.gpuUtilCompute = r.readDouble();
    else if (field === 59 && wire === 0) m.hasGpuUtilCopy = setBool();
    else if (field === 60 && wire === 1) m.gpuUtilCopy = r.readDouble();
    else if (field === 61 && wire === 0) m.hasGpuUtilVideoDecode = setBool();
    else if (field === 62 && wire === 1) m.gpuUtilVideoDecode = r.readDouble();
    else if (field === 63 && wire === 0) m.hasGpuUtilVideoEncode = setBool();
    else if (field === 64 && wire === 1) m.gpuUtilVideoEncode = r.readDouble();
    else if (field === 65 && wire === 0) m.hasGpuDedicatedUsed = setBool();
    else if (field === 66 && wire === 0) m.gpuDedicatedUsedBytes = setU64();
    else if (field === 67 && wire === 0) m.hasGpuSharedUsed = setBool();
    else if (field === 68 && wire === 0) m.gpuSharedUsedBytes = setU64();
    else if (field === 73 && wire === 0) m.hasGpuFanRpm = setBool();
    else if (field === 74 && wire === 1) m.gpuFanRpm = r.readDouble();
    else if (field === 85 && wire === 0) m.hasNetUtilizationPercent = setBool();
    else if (field === 86 && wire === 1)
      m.netUtilizationPercent = r.readDouble();
    else if (field === 115 && wire === 0) m.hasDiskSmartOk = setBool();
    else if (field === 116 && wire === 0) m.diskSmartOk = setBool();
    else r.skip(wire);
  }
  return m;
}

export function decodeHealthSnapshot(data: Uint8Array): HealthSnapshot {
  const r = new Reader(data);
  const snap: HealthSnapshot = {
    info: emptyStaticInfo(),
    sample: emptySample(),
  };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 2)
      snap.info = decodeHealthStaticInfo(r.readBytes());
    else if (field === 2 && wire === 2)
      snap.sample = decodeHealthSample(r.readBytes());
    else r.skip(wire);
  }
  return snap;
}

export function decodeHealthProcessEntry(data: Uint8Array): HealthProcessEntry {
  const r = new Reader(data);
  const m = emptyProcessEntry();
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    const setBool = () => r.readVarint() !== 0;
    const setU64 = () => Number(r.readVarintBig());
    if (field === 1 && wire === 0) m.pid = r.readVarint();
    else if (field === 2 && wire === 2) m.name = r.readString();
    else if (field === 3 && wire === 0) m.hasCpuPercent = setBool();
    else if (field === 4 && wire === 1) m.cpuPercent = r.readDouble();
    else if (field === 5 && wire === 0) m.hasMemoryBytes = setBool();
    else if (field === 6 && wire === 0) m.memoryBytes = setU64();
    else if (field === 7 && wire === 0) m.hasGpuPercent = setBool();
    else if (field === 8 && wire === 1) m.gpuPercent = r.readDouble();
    else if (field === 9 && wire === 0) m.hasDiskBps = setBool();
    else if (field === 10 && wire === 1) m.diskBps = r.readDouble();
    else if (field === 11 && wire === 0) m.hasNetBps = setBool();
    else if (field === 12 && wire === 1) m.netBps = r.readDouble();
    else if (field === 13 && wire === 2) m.path = r.readString();
    else if (field === 14 && wire === 0) m.threadCount = r.readVarint();
    else if (field === 15 && wire === 0) m.handleCount = r.readVarint();
    else if (field === 16 && wire === 0) m.hasCreateTime = setBool();
    else if (field === 17 && wire === 0) m.createTimeUnixMs = setU64();
    else if (field === 18 && wire === 0) m.hasIsCritical = setBool();
    else if (field === 19 && wire === 0) m.isCritical = setBool();
    else if (field === 20 && wire === 0) m.hasWorkingSetBytes = setBool();
    else if (field === 21 && wire === 0) m.workingSetBytes = setU64();
    else if (field === 22 && wire === 0) m.hasCommitBytes = setBool();
    else if (field === 23 && wire === 0) m.commitBytes = setU64();
    else if (field === 24 && wire === 0) m.hasPagedPoolBytes = setBool();
    else if (field === 25 && wire === 0) m.pagedPoolBytes = setU64();
    else if (field === 26 && wire === 0) m.hasNonpagedPoolBytes = setBool();
    else if (field === 27 && wire === 0) m.nonpagedPoolBytes = setU64();
    else if (field === 28 && wire === 0) m.hasGpuDedicatedBytes = setBool();
    else if (field === 29 && wire === 0) m.gpuDedicatedBytes = setU64();
    else if (field === 30 && wire === 0) m.hasGpuSharedBytes = setBool();
    else if (field === 31 && wire === 0) m.gpuSharedBytes = setU64();
    else if (field === 32 && wire === 2) m.gpuEngine = r.readString();
    else if (field === 33 && wire === 0) m.hasNetUploadBps = setBool();
    else if (field === 34 && wire === 1) m.netUploadBps = r.readDouble();
    else if (field === 35 && wire === 0) m.hasNetDownloadBps = setBool();
    else if (field === 36 && wire === 1) m.netDownloadBps = r.readDouble();
    else if (field === 37 && wire === 0) m.hasNetBytesTotal = setBool();
    else if (field === 38 && wire === 0) m.netBytesTotal = setU64();
    else r.skip(wire);
  }
  return m;
}

export function decodeHealthProcessInventory(
  data: Uint8Array,
): HealthProcessInventoryUpdate {
  const r = new Reader(data);
  const m: HealthProcessInventoryUpdate = {
    seq: 0,
    fullResync: false,
    upserts: [],
    removedPids: [],
  };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 0) m.seq = Number(r.readVarintBig());
    else if (field === 2 && wire === 0) m.fullResync = r.readVarint() !== 0;
    else if (field === 3 && wire === 2)
      m.upserts.push(decodeHealthProcessEntry(r.readBytes()));
    else if (field === 4 && wire === 0) m.removedPids.push(r.readVarint());
    else if (field === 4 && wire === 2) {
      // packed repeated uint32
      const packed = r.readBytes();
      const pr = new Reader(packed);
      while (pr.hasMore) m.removedPids.push(pr.readVarint());
    } else r.skip(wire);
  }
  return m;
}

export function decodeHealthUpdate(data: Uint8Array): HealthUpdateDecoded {
  const r = new Reader(data);
  let sample = emptySample();
  let inventory: HealthProcessInventoryUpdate | null = null;
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 2) sample = decodeHealthSample(r.readBytes());
    else if (field === 2 && wire === 2)
      inventory = decodeHealthProcessInventory(r.readBytes());
    else r.skip(wire);
  }
  return { sample, inventory };
}

/** @deprecated use decodeHealthUpdate */
export function decodeHealthUpdateSample(data: Uint8Array): HealthSample {
  return decodeHealthUpdate(data).sample;
}

export function decodeProcessDetails(data: Uint8Array): ProcessDetails {
  const r = new Reader(data);
  const m = emptyProcessDetails();
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    const setBool = () => r.readVarint() !== 0;
    const setU64 = () => Number(r.readVarintBig());
    if (field === 1 && wire === 0) m.pid = r.readVarint();
    else if (field === 2 && wire === 2) m.name = r.readString();
    else if (field === 3 && wire === 2) m.path = r.readString();
    else if (field === 4 && wire === 2) m.company = r.readString();
    else if (field === 5 && wire === 2) m.commandLine = r.readString();
    else if (field === 6 && wire === 0) m.hasCreateTime = setBool();
    else if (field === 7 && wire === 0) m.createTimeUnixMs = setU64();
    else if (field === 8 && wire === 0) m.threadCount = r.readVarint();
    else if (field === 9 && wire === 0) m.handleCount = r.readVarint();
    else if (field === 10 && wire === 0) m.hasPath = setBool();
    else if (field === 11 && wire === 0) m.hasCompany = setBool();
    else if (field === 12 && wire === 0) m.hasCommandLine = setBool();
    else if (field === 13 && wire === 0) m.parentPid = r.readVarint();
    else if (field === 14 && wire === 0) m.hasParentPid = setBool();
    else if (field === 15 && wire === 2) m.parentName = r.readString();
    else if (field === 16 && wire === 0) m.hasParentName = setBool();
    else if (field === 17 && wire === 2) m.user = r.readString();
    else if (field === 18 && wire === 0) m.hasUser = setBool();
    else if (field === 19 && wire === 2) m.integrityLevel = r.readString();
    else if (field === 20 && wire === 0) m.hasIntegrityLevel = setBool();
    else if (field === 21 && wire === 0) m.elevated = setBool();
    else if (field === 22 && wire === 0) m.hasElevated = setBool();
    else if (field === 23 && wire === 2) m.architecture = r.readString();
    else if (field === 24 && wire === 0) m.hasArchitecture = setBool();
    else if (field === 25 && wire === 2) m.productName = r.readString();
    else if (field === 26 && wire === 0) m.hasProductName = setBool();
    else r.skip(wire);
  }
  return m;
}
