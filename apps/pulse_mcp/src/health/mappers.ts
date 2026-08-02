import type { HealthSample, HealthSnapshot, HealthStaticInfo } from "./types.js";

function isoUtcFromUnixMs(ms: number): string {
  if (!ms || ms <= 0) return new Date().toISOString();
  return new Date(ms).toISOString();
}

export function mapCpu(sample: HealthSample, info: HealthStaticInfo) {
  const unavailableFields: Record<string, string> = {};
  if (!sample.hasCpuTempC) {
    unavailableFields.temperatureCelsius = "Not supported";
  }
  return {
    observedAt: isoUtcFromUnixMs(sample.unixMs),
    usagePercent: sample.hasCpuPercent ? sample.cpuPercent : null,
    usageKernelPercent: null,
    usageUserPercent: null,
    logicalProcessors:
      info.cpuLogicalProcessors > 0 ? info.cpuLogicalProcessors : null,
    cores: info.cpuCores > 0 ? info.cpuCores : null,
    frequencyMHz: sample.hasCpuCurrentMhz
      ? sample.cpuCurrentMhz
      : info.cpuBaseMhz > 0
        ? info.cpuBaseMhz
        : null,
    temperatureCelsius: sample.hasCpuTempC ? sample.cpuTempC : null,
    perCorePercent:
      sample.cpuCorePercent.length > 0 ? [...sample.cpuCorePercent] : null,
    unavailable:
      Object.keys(unavailableFields).length > 0 ? unavailableFields : undefined,
  };
}

export function mapMemory(sample: HealthSample, info: HealthStaticInfo) {
  const total =
    sample.memoryTotalBytes > 0
      ? sample.memoryTotalBytes
      : info.installedRamBytes > 0
        ? info.installedRamBytes
        : null;
  const used = sample.memoryUsedBytes > 0 ? sample.memoryUsedBytes : null;
  const usagePercent =
    total && used != null ? (used / total) * 100 : null;
  return {
    observedAt: isoUtcFromUnixMs(sample.unixMs),
    totalBytes: total,
    inUseBytes: used,
    availableBytes:
      sample.memoryAvailableBytes > 0 ? sample.memoryAvailableBytes : null,
    usagePercent,
    commitTotalBytes: sample.hasMemoryCommitted
      ? sample.memoryCommittedBytes
      : null,
    commitLimitBytes: sample.hasMemoryCommitted
      ? sample.memoryCommitLimitBytes
      : null,
    pooledPagedBytes: sample.hasMemoryPagedPool
      ? sample.memoryPagedPoolBytes
      : null,
    pooledNonPagedBytes: sample.hasMemoryNonpagedPool
      ? sample.memoryNonpagedPoolBytes
      : null,
    compressedBytes: sample.hasMemoryCompressed
      ? sample.memoryCompressedBytes
      : null,
  };
}

export function mapGpu(sample: HealthSample, info: HealthStaticInfo) {
  const engines: Array<{ name: string; usagePercent: number | null }> = [];
  if (sample.hasGpuUtil3d)
    engines.push({ name: "3D", usagePercent: sample.gpuUtil3d });
  if (sample.hasGpuUtilCompute)
    engines.push({ name: "Compute", usagePercent: sample.gpuUtilCompute });
  if (sample.hasGpuUtilCopy)
    engines.push({ name: "Copy", usagePercent: sample.gpuUtilCopy });
  if (sample.hasGpuUtilVideoDecode)
    engines.push({
      name: "VideoDecode",
      usagePercent: sample.gpuUtilVideoDecode,
    });
  if (sample.hasGpuUtilVideoEncode)
    engines.push({
      name: "VideoEncode",
      usagePercent: sample.gpuUtilVideoEncode,
    });

  const unavailableFields: Record<string, string> = {};
  if (!sample.hasGpuTempC)
    unavailableFields.temperatureCelsius = "Not supported";
  if (!sample.hasGpuFanRpm) unavailableFields.fanRpm = "Not supported";

  return {
    observedAt: isoUtcFromUnixMs(sample.unixMs),
    adapters: [
      {
        index: 0,
        name: info.gpuModel || null,
        usagePercent: sample.hasGpuPercent ? sample.gpuPercent : null,
        dedicatedMemoryBytes: sample.hasGpuDedicatedUsed
          ? sample.gpuDedicatedUsedBytes
          : info.gpuDedicatedBytes > 0
            ? info.gpuDedicatedBytes
            : null,
        sharedMemoryBytes: sample.hasGpuSharedUsed
          ? sample.gpuSharedUsedBytes
          : info.gpuSharedBytes > 0
            ? info.gpuSharedBytes
            : null,
        temperatureCelsius: sample.hasGpuTempC ? sample.gpuTempC : null,
        fanRpm: sample.hasGpuFanRpm ? sample.gpuFanRpm : null,
        driverVersion: info.gpuDriverVersion || null,
        engines: engines.length > 0 ? engines : null,
        unavailable:
          Object.keys(unavailableFields).length > 0
            ? unavailableFields
            : undefined,
      },
    ],
    note: "Pulse Health reports the primary GPU adapter only (see GitHub #9).",
  };
}

export function mapStorage(sample: HealthSample, info: HealthStaticInfo) {
  return {
    observedAt: isoUtcFromUnixMs(sample.unixMs),
    summary: {
      usedBytes: sample.diskUsedBytes > 0 ? sample.diskUsedBytes : null,
      totalBytes:
        sample.diskTotalBytes > 0
          ? sample.diskTotalBytes
          : info.primaryStorageBytes > 0
            ? info.primaryStorageBytes
            : null,
      readBytesPerSec: sample.hasDiskReadBps ? sample.diskReadBps : null,
      writeBytesPerSec: sample.hasDiskWriteBps ? sample.diskWriteBps : null,
      ssdTemperatureCelsius: sample.hasSsdTempC ? sample.ssdTempC : null,
      smartOk: sample.hasDiskSmartOk ? sample.diskSmartOk : null,
      unavailable: !sample.hasSsdTempC
        ? { ssdTemperatureCelsius: "Not supported" }
        : undefined,
    },
    volumes: sample.volumes.map((v) => ({
      id: v.id,
      mountPoint: v.mountPoint,
      label: v.label || null,
      fileSystem: v.fileSystem || null,
      kind: v.kind,
      usedBytes: v.hasCapacity ? v.usedBytes : null,
      totalBytes: v.hasCapacity ? v.totalBytes : null,
      hasCapacity: v.hasCapacity,
      includedInSummary: v.includedInSummary,
    })),
    disks: sample.disks.map((d) => ({
      id: d.id,
      name: d.name || null,
      readBytesPerSec: d.hasReadBps ? d.readBps : null,
      writeBytesPerSec: d.hasWriteBps ? d.writeBps : null,
    })),
  };
}

export function mapNetwork(sample: HealthSample, info: HealthStaticInfo) {
  return {
    observedAt: isoUtcFromUnixMs(sample.unixMs),
    adapterName: info.activeNetworkAdapter || null,
    downloadBytesPerSec: sample.hasNetDownloadBps
      ? sample.netDownloadBps
      : null,
    uploadBytesPerSec: sample.hasNetUploadBps ? sample.netUploadBps : null,
    utilizationPercent: sample.hasNetUtilizationPercent
      ? sample.netUtilizationPercent
      : null,
    ipv4: sample.ipv4 || null,
    ipv6: sample.ipv6 || null,
    gateway: sample.gateway || null,
    dns: sample.dns || null,
  };
}

export function mapHealth(
  snap: HealthSnapshot,
  sections?: string[],
) {
  const want = new Set(
    (sections && sections.length > 0
      ? sections
      : ["cpu", "memory", "gpu", "storage", "network", "static"]
    ).map((s) => s.toLowerCase()),
  );
  const { info, sample } = snap;
  const data: Record<string, unknown> = {
    observedAt: isoUtcFromUnixMs(sample.unixMs),
  };
  if (want.has("static")) {
    data.static = {
      os: {
        name: info.windowsEdition || null,
        build: info.windowsVersion || null,
        architecture: info.cpuArchitecture || null,
      },
      cpu: {
        name: info.cpuModel || null,
        cores: info.cpuCores > 0 ? info.cpuCores : null,
        logicalProcessors:
          info.cpuLogicalProcessors > 0 ? info.cpuLogicalProcessors : null,
      },
      memory: {
        totalBytes: info.installedRamBytes > 0 ? info.installedRamBytes : null,
      },
      gpu: [
        {
          name: info.gpuModel || null,
          driverVersion: info.gpuDriverVersion || null,
        },
      ],
    };
  }
  if (want.has("cpu")) data.cpu = mapCpu(sample, info);
  if (want.has("memory")) data.memory = mapMemory(sample, info);
  if (want.has("gpu")) data.gpu = mapGpu(sample, info);
  if (want.has("storage")) data.storage = mapStorage(sample, info);
  if (want.has("network")) data.network = mapNetwork(sample, info);
  return data;
}
