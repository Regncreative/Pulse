/** Decoded Health Engine types (subset used by MCP M2). */

export interface HealthVolume {
  id: string;
  mountPoint: string;
  label: string;
  fileSystem: string;
  kind: number;
  usedBytes: number;
  totalBytes: number;
  hasCapacity: boolean;
  includedInSummary: boolean;
}

export interface HealthPhysicalDisk {
  id: string;
  name: string;
  hasReadBps: boolean;
  readBps: number;
  hasWriteBps: boolean;
  writeBps: number;
}

export interface HealthStaticInfo {
  windowsEdition: string;
  windowsVersion: string;
  cpuModel: string;
  gpuModel: string;
  installedRamBytes: number;
  primaryStorageBytes: number;
  activeNetworkAdapter: string;
  cpuBaseMhz: number;
  cpuSockets: number;
  cpuCores: number;
  cpuLogicalProcessors: number;
  cpuArchitecture: string;
  gpuDriverVersion: string;
  gpuDedicatedBytes: number;
  gpuSharedBytes: number;
}

export interface HealthSample {
  unixMs: number;
  hasCpuPercent: boolean;
  cpuPercent: number;
  memoryUsedBytes: number;
  memoryTotalBytes: number;
  hasGpuPercent: boolean;
  gpuPercent: number;
  hasNetDownloadBps: boolean;
  netDownloadBps: number;
  hasNetUploadBps: boolean;
  netUploadBps: number;
  hasDiskReadBps: boolean;
  diskReadBps: number;
  hasDiskWriteBps: boolean;
  diskWriteBps: number;
  diskUsedBytes: number;
  diskTotalBytes: number;
  uptimeMs: number;
  hasCpuTempC: boolean;
  cpuTempC: number;
  hasGpuTempC: boolean;
  gpuTempC: number;
  hasSsdTempC: boolean;
  ssdTempC: number;
  hasCpuCurrentMhz: boolean;
  cpuCurrentMhz: number;
  memoryAvailableBytes: number;
  hasMemoryCommitted: boolean;
  memoryCommittedBytes: number;
  memoryCommitLimitBytes: number;
  hasMemoryPagedPool: boolean;
  memoryPagedPoolBytes: number;
  hasMemoryNonpagedPool: boolean;
  memoryNonpagedPoolBytes: number;
  hasMemoryCompressed: boolean;
  memoryCompressedBytes: number;
  ipv4: string;
  ipv6: string;
  gateway: string;
  dns: string;
  cpuCorePercent: number[];
  volumes: HealthVolume[];
  disks: HealthPhysicalDisk[];
  hasGpuUtil3d: boolean;
  gpuUtil3d: number;
  hasGpuUtilCompute: boolean;
  gpuUtilCompute: number;
  hasGpuUtilCopy: boolean;
  gpuUtilCopy: number;
  hasGpuUtilVideoDecode: boolean;
  gpuUtilVideoDecode: number;
  hasGpuUtilVideoEncode: boolean;
  gpuUtilVideoEncode: number;
  hasGpuDedicatedUsed: boolean;
  gpuDedicatedUsedBytes: number;
  hasGpuSharedUsed: boolean;
  gpuSharedUsedBytes: number;
  hasGpuFanRpm: boolean;
  gpuFanRpm: number;
  hasNetUtilizationPercent: boolean;
  netUtilizationPercent: number;
  hasDiskSmartOk: boolean;
  diskSmartOk: boolean;
}

export interface HealthSnapshot {
  info: HealthStaticInfo;
  sample: HealthSample;
}

export function emptyStaticInfo(): HealthStaticInfo {
  return {
    windowsEdition: "",
    windowsVersion: "",
    cpuModel: "",
    gpuModel: "",
    installedRamBytes: 0,
    primaryStorageBytes: 0,
    activeNetworkAdapter: "",
    cpuBaseMhz: 0,
    cpuSockets: 0,
    cpuCores: 0,
    cpuLogicalProcessors: 0,
    cpuArchitecture: "",
    gpuDriverVersion: "",
    gpuDedicatedBytes: 0,
    gpuSharedBytes: 0,
  };
}

export function emptySample(): HealthSample {
  return {
    unixMs: 0,
    hasCpuPercent: false,
    cpuPercent: 0,
    memoryUsedBytes: 0,
    memoryTotalBytes: 0,
    hasGpuPercent: false,
    gpuPercent: 0,
    hasNetDownloadBps: false,
    netDownloadBps: 0,
    hasNetUploadBps: false,
    netUploadBps: 0,
    hasDiskReadBps: false,
    diskReadBps: 0,
    hasDiskWriteBps: false,
    diskWriteBps: 0,
    diskUsedBytes: 0,
    diskTotalBytes: 0,
    uptimeMs: 0,
    hasCpuTempC: false,
    cpuTempC: 0,
    hasGpuTempC: false,
    gpuTempC: 0,
    hasSsdTempC: false,
    ssdTempC: 0,
    hasCpuCurrentMhz: false,
    cpuCurrentMhz: 0,
    memoryAvailableBytes: 0,
    hasMemoryCommitted: false,
    memoryCommittedBytes: 0,
    memoryCommitLimitBytes: 0,
    hasMemoryPagedPool: false,
    memoryPagedPoolBytes: 0,
    hasMemoryNonpagedPool: false,
    memoryNonpagedPoolBytes: 0,
    hasMemoryCompressed: false,
    memoryCompressedBytes: 0,
    ipv4: "",
    ipv6: "",
    gateway: "",
    dns: "",
    cpuCorePercent: [],
    volumes: [],
    disks: [],
    hasGpuUtil3d: false,
    gpuUtil3d: 0,
    hasGpuUtilCompute: false,
    gpuUtilCompute: 0,
    hasGpuUtilCopy: false,
    gpuUtilCopy: 0,
    hasGpuUtilVideoDecode: false,
    gpuUtilVideoDecode: 0,
    hasGpuUtilVideoEncode: false,
    gpuUtilVideoEncode: 0,
    hasGpuDedicatedUsed: false,
    gpuDedicatedUsedBytes: 0,
    hasGpuSharedUsed: false,
    gpuSharedUsedBytes: 0,
    hasGpuFanRpm: false,
    gpuFanRpm: 0,
    hasNetUtilizationPercent: false,
    netUtilizationPercent: 0,
    hasDiskSmartOk: false,
    diskSmartOk: false,
  };
}
