/// Minimal protobuf wire codec for pulse.ipc.Envelope (matches C++ pulse_wire).

import 'dart:convert';
import 'dart:typed_data';

class ClientHello {
  ClientHello({
    this.protocolVersion = 1,
    this.clientName = '',
    this.clientVersion = '',
  });
  int protocolVersion;
  String clientName;
  String clientVersion;
}

class ServerHello {
  ServerHello({this.protocolVersion = 1, this.serviceVersion = ''});
  int protocolVersion;
  String serviceVersion;
}

class Ping {
  Ping({this.nonce = 0, this.unixMs = 0});
  int nonce;
  int unixMs;
}

class Pong {
  Pong({this.nonce = 0, this.unixMs = 0, this.serviceVersion = ''});
  int nonce;
  int unixMs;
  String serviceVersion;
}

class Heartbeat {
  Heartbeat({this.unixMs = 0});
  int unixMs;
}

class ErrorResponse {
  ErrorResponse({
    this.code = 0,
    this.message = '',
    this.technicalDetail = '',
    this.component = '',
  });
  int code;
  String message;
  String technicalDetail;
  String component;
}

/// Matches pulse.ipc.Severity / C++ Severity.
class Severity {
  static const int unknown = 0;
  static const int info = 1;
  static const int warning = 2;
  static const int error = 3;
  static const int critical = 4;
  static const int verbose = 5;
}

/// Matches pulse.ipc.Importance / C++ Importance.
class Importance {
  static const int low = 0;
  static const int medium = 1;
  static const int high = 2;
  static const int critical = 3;
}

class TimelineEvent {
  TimelineEvent({
    this.eventId = '',
    this.timestampUnixMs = 0,
    this.timestampIso = '',
    this.severity = Severity.unknown,
    this.channel = '',
    this.providerName = '',
    this.winEventId = 0,
    this.recordId = 0,
    this.computerName = '',
    this.summary = '',
    this.technicalSummary = '',
    this.message = '',
    this.title = '',
    this.recommendation = '',
    this.actionRequired = false,
    this.importance = Importance.low,
    this.category = '',
  });
  String eventId;
  int timestampUnixMs;
  String timestampIso;
  int severity;
  String channel;
  String providerName;
  int winEventId;
  int recordId;
  String computerName;
  String summary;
  String technicalSummary;
  String message;
  String title;
  String recommendation;
  bool actionRequired;
  int importance;
  String category;
}

class GetTimelineSnapshot {
  GetTimelineSnapshot({this.limit = 100, this.channel = 'System'});
  int limit;
  String channel;
}

class TimelineSnapshot {
  TimelineSnapshot({
    List<TimelineEvent>? events,
    this.channel = '',
    this.requestedLimit = 0,
    this.collectedUnixMs = 0,
  }) : events = events ?? <TimelineEvent>[];
  List<TimelineEvent> events;
  String channel;
  int requestedLimit;
  int collectedUnixMs;
}

class StartLiveMonitoring {
  StartLiveMonitoring({this.channel = 'System'});
  String channel;
}

class StopLiveMonitoring {
  StopLiveMonitoring();
}

class HealthStaticInfo {
  HealthStaticInfo({
    this.windowsEdition = '',
    this.windowsVersion = '',
    this.cpuModel = '',
    this.gpuModel = '',
    this.installedRamBytes = 0,
    this.primaryStorageBytes = 0,
    this.activeNetworkAdapter = '',
    this.cpuBaseMhz = 0,
    this.cpuSockets = 0,
    this.cpuCores = 0,
    this.cpuLogicalProcessors = 0,
    this.cpuVirtualizationEnabled = false,
    this.gpuDedicatedBytes = 0,
    this.gpuSharedBytes = 0,
    this.cpuArchitecture = '',
    this.cpuInstructionSet = '',
    this.cpuNumaNodes = 0,
    this.hasCpuSmt = false,
    this.cpuSmtEnabled = false,
    this.hasCpuL1Cache = false,
    this.cpuL1CacheBytes = 0,
    this.hasCpuL2Cache = false,
    this.cpuL2CacheBytes = 0,
    this.hasCpuL3Cache = false,
    this.cpuL3CacheBytes = 0,
    this.cpuVirtualizationVendor = '',
    this.gpuVendor = '',
    this.gpuDriverVersion = '',
    this.gpuDriverDate = '',
    this.hasGpuLuid = false,
    this.gpuLuidHigh = 0,
    this.gpuLuidLow = 0,
    this.gpuDirectxVersion = '',
    this.gpuWddmVersion = '',
    this.hasGpuHardwareScheduling = false,
    this.gpuHardwareScheduling = false,
    this.gpuPcieLinkSpeed = '',
    this.gpuPcieLinkWidth = '',
    this.netManufacturer = '',
    this.netDescription = '',
    this.netMacAddress = '',
    this.netDriverVersion = '',
    this.netDriverDate = '',
    this.netConnectionType = '',
    this.netDuplex = '',
    this.hasNetMtu = false,
    this.netMtu = 0,
    this.hasNetIfIndex = false,
    this.netIfIndex = 0,
    this.hasNetLinkSpeedBps = false,
    this.netLinkSpeedBps = 0,
    this.hasNetDhcp = false,
    this.netDhcpEnabled = false,
    this.netDhcpServer = '',
    this.hasNetLeaseObtained = false,
    this.netLeaseObtainedUnixMs = 0,
    this.hasNetLeaseExpires = false,
    this.netLeaseExpiresUnixMs = 0,
    this.hasMemSlotsUsed = false,
    this.memSlotsUsed = 0,
    this.hasMemModuleCount = false,
    this.memModuleCount = 0,
    this.memDdrGeneration = '',
    this.hasMemSpeedMhz = false,
    this.memSpeedMhz = 0,
    this.memFormFactor = '',
    this.hasMemEcc = false,
    this.memEcc = false,
    this.hasMemChannels = false,
    this.memChannels = 0,
    this.memDimmVendor = '',
    this.memDimmPartNumber = '',
    this.memDimmSerial = '',
    this.diskInterface = '',
    this.diskBus = '',
    this.diskModel = '',
    this.diskSerial = '',
    this.diskFirmware = '',
    this.diskPartitionStyle = '',
    this.hasDiskSectorSize = false,
    this.diskSectorSize = 0,
    this.hasDiskRotationRate = false,
    this.diskRotationRate = 0,
    this.hasDiskTrim = false,
    this.diskTrimSupported = false,
    this.gpuPciLocation = '',
    this.hasGpuResizableBar = false,
    this.gpuResizableBar = false,
  });
  String windowsEdition;
  String windowsVersion;
  String cpuModel;
  String gpuModel;
  int installedRamBytes;
  int primaryStorageBytes;
  String activeNetworkAdapter;
  int cpuBaseMhz;
  int cpuSockets;
  int cpuCores;
  int cpuLogicalProcessors;
  bool cpuVirtualizationEnabled;
  int gpuDedicatedBytes;
  int gpuSharedBytes;
  String cpuArchitecture;
  String cpuInstructionSet;
  int cpuNumaNodes;
  bool hasCpuSmt;
  bool cpuSmtEnabled;
  bool hasCpuL1Cache;
  int cpuL1CacheBytes;
  bool hasCpuL2Cache;
  int cpuL2CacheBytes;
  bool hasCpuL3Cache;
  int cpuL3CacheBytes;
  String cpuVirtualizationVendor;
  String gpuVendor;
  String gpuDriverVersion;
  String gpuDriverDate;
  bool hasGpuLuid;
  int gpuLuidHigh;
  int gpuLuidLow;
  String gpuDirectxVersion;
  String gpuWddmVersion;
  bool hasGpuHardwareScheduling;
  bool gpuHardwareScheduling;
  String gpuPcieLinkSpeed;
  String gpuPcieLinkWidth;
  String gpuPciLocation;
  bool hasGpuResizableBar;
  bool gpuResizableBar;
  String netManufacturer;
  String netDescription;
  String netMacAddress;
  String netDriverVersion;
  String netDriverDate;
  String netConnectionType;
  String netDuplex;
  bool hasNetMtu;
  int netMtu;
  bool hasNetIfIndex;
  int netIfIndex;
  bool hasNetLinkSpeedBps;
  int netLinkSpeedBps;
  bool hasNetDhcp;
  bool netDhcpEnabled;
  String netDhcpServer;
  bool hasNetLeaseObtained;
  int netLeaseObtainedUnixMs;
  bool hasNetLeaseExpires;
  int netLeaseExpiresUnixMs;
  bool hasMemSlotsUsed;
  int memSlotsUsed;
  bool hasMemModuleCount;
  int memModuleCount;
  String memDdrGeneration;
  bool hasMemSpeedMhz;
  int memSpeedMhz;
  String memFormFactor;
  bool hasMemEcc;
  bool memEcc;
  bool hasMemChannels;
  int memChannels;
  String memDimmVendor;
  String memDimmPartNumber;
  String memDimmSerial;
  String diskInterface;
  String diskBus;
  String diskModel;
  String diskSerial;
  String diskFirmware;
  String diskPartitionStyle;
  bool hasDiskSectorSize;
  int diskSectorSize;
  bool hasDiskRotationRate;
  int diskRotationRate;
  bool hasDiskTrim;
  bool diskTrimSupported;
}

class HealthProcessEntry {
  HealthProcessEntry({
    this.pid = 0,
    this.name = '',
    this.hasCpuPercent = false,
    this.cpuPercent = 0.0,
    this.hasMemoryBytes = false,
    this.memoryBytes = 0,
    this.hasGpuPercent = false,
    this.gpuPercent = 0.0,
    this.hasDiskBps = false,
    this.diskBps = 0.0,
    this.hasNetBps = false,
    this.netBps = 0.0,
    this.path = '',
    this.threadCount = 0,
    this.handleCount = 0,
    this.hasCreateTime = false,
    this.createTimeUnixMs = 0,
    this.hasIsCritical = false,
    this.isCritical = false,
    this.hasWorkingSetBytes = false,
    this.workingSetBytes = 0,
    this.hasCommitBytes = false,
    this.commitBytes = 0,
    this.hasPagedPoolBytes = false,
    this.pagedPoolBytes = 0,
    this.hasNonpagedPoolBytes = false,
    this.nonpagedPoolBytes = 0,
    this.hasGpuDedicatedBytes = false,
    this.gpuDedicatedBytes = 0,
    this.hasGpuSharedBytes = false,
    this.gpuSharedBytes = 0,
    this.gpuEngine = '',
  });
  int pid;
  String name;
  bool hasCpuPercent;
  double cpuPercent;
  bool hasMemoryBytes;
  int memoryBytes;
  bool hasGpuPercent;
  double gpuPercent;
  bool hasDiskBps;
  double diskBps;
  bool hasNetBps;
  double netBps;
  String path;
  int threadCount;
  int handleCount;
  bool hasCreateTime;
  int createTimeUnixMs;
  bool hasIsCritical;
  bool isCritical;
  bool hasWorkingSetBytes;
  int workingSetBytes;
  bool hasCommitBytes;
  int commitBytes;
  bool hasPagedPoolBytes;
  int pagedPoolBytes;
  bool hasNonpagedPoolBytes;
  int nonpagedPoolBytes;
  bool hasGpuDedicatedBytes;
  int gpuDedicatedBytes;
  bool hasGpuSharedBytes;
  int gpuSharedBytes;
  String gpuEngine;
}

class HealthProcessInventoryUpdate {
  HealthProcessInventoryUpdate({
    this.seq = 0,
    this.fullResync = false,
    List<HealthProcessEntry>? upserts,
    List<int>? removedPids,
  }) : upserts = upserts ?? <HealthProcessEntry>[],
       removedPids = removedPids ?? <int>[];
  int seq;
  bool fullResync;
  List<HealthProcessEntry> upserts;
  List<int> removedPids;
}

class GetProcessDetails {
  GetProcessDetails({this.pid = 0});
  int pid;
}

class ProcessDetails {
  ProcessDetails({
    this.pid = 0,
    this.name = '',
    this.path = '',
    this.company = '',
    this.commandLine = '',
    this.hasCreateTime = false,
    this.createTimeUnixMs = 0,
    this.threadCount = 0,
    this.handleCount = 0,
    this.hasPath = false,
    this.hasCompany = false,
    this.hasCommandLine = false,
    this.parentPid = 0,
    this.hasParentPid = false,
    this.parentName = '',
    this.hasParentName = false,
    this.user = '',
    this.hasUser = false,
    this.integrityLevel = '',
    this.hasIntegrityLevel = false,
    this.elevated = false,
    this.hasElevated = false,
    this.architecture = '',
    this.hasArchitecture = false,
    this.productName = '',
    this.hasProductName = false,
  });
  int pid;
  String name;
  String path;
  String company;
  String commandLine;
  bool hasCreateTime;
  int createTimeUnixMs;
  int threadCount;
  int handleCount;
  bool hasPath;
  bool hasCompany;
  bool hasCommandLine;
  int parentPid;
  bool hasParentPid;
  String parentName;
  bool hasParentName;
  String user;
  bool hasUser;
  String integrityLevel;
  bool hasIntegrityLevel;
  bool elevated;
  bool hasElevated;
  String architecture;
  bool hasArchitecture;
  String productName;
  bool hasProductName;
}

enum HealthDriveKind {
  unspecified,
  fixed,
  removable,
  remote,
  cdrom,
  ramdisk,
  unknown,
}

HealthDriveKind healthDriveKindFromWire(int v) {
  if (v < 0 || v >= HealthDriveKind.values.length) {
    return HealthDriveKind.unspecified;
  }
  return HealthDriveKind.values[v];
}

class HealthVolume {
  HealthVolume({
    this.id = '',
    this.mountPoint = '',
    this.label = '',
    this.fileSystem = '',
    this.kind = HealthDriveKind.unspecified,
    this.usedBytes = 0,
    this.totalBytes = 0,
    this.hasCapacity = false,
    this.includedInSummary = false,
  });

  String id;
  String mountPoint;
  String label;
  String fileSystem;
  HealthDriveKind kind;
  int usedBytes;
  int totalBytes;
  bool hasCapacity;
  bool includedInSummary;
}

class HealthPhysicalDisk {
  HealthPhysicalDisk({
    this.id = '',
    this.name = '',
    this.hasReadBps = false,
    this.readBps = 0.0,
    this.hasWriteBps = false,
    this.writeBps = 0.0,
  });

  String id;
  String name;
  bool hasReadBps;
  double readBps;
  bool hasWriteBps;
  double writeBps;
}

class HealthSample {
  HealthSample({
    this.unixMs = 0,
    this.hasCpuPercent = false,
    this.cpuPercent = 0.0,
    this.memoryUsedBytes = 0,
    this.memoryTotalBytes = 0,
    this.hasGpuPercent = false,
    this.gpuPercent = 0.0,
    this.hasNetDownloadBps = false,
    this.netDownloadBps = 0.0,
    this.hasNetUploadBps = false,
    this.netUploadBps = 0.0,
    this.hasDiskReadBps = false,
    this.diskReadBps = 0.0,
    this.hasDiskWriteBps = false,
    this.diskWriteBps = 0.0,
    this.diskUsedBytes = 0,
    this.diskTotalBytes = 0,
    this.uptimeMs = 0,
    this.hasCpuTempC = false,
    this.cpuTempC = 0.0,
    this.hasGpuTempC = false,
    this.gpuTempC = 0.0,
    this.hasSsdTempC = false,
    this.ssdTempC = 0.0,
    this.hasCpuCurrentMhz = false,
    this.cpuCurrentMhz = 0.0,
    this.memoryAvailableBytes = 0,
    this.hasMemoryCommitted = false,
    this.memoryCommittedBytes = 0,
    this.memoryCommitLimitBytes = 0,
    this.hasMemoryCached = false,
    this.memoryCachedBytes = 0,
    this.ipv4 = '',
    this.ipv6 = '',
    this.gateway = '',
    this.dns = '',
    List<HealthProcessEntry>? topCpu,
    List<HealthProcessEntry>? topMemory,
    List<HealthProcessEntry>? topGpu,
    List<HealthProcessEntry>? topDisk,
    List<HealthProcessEntry>? topNetwork,
    List<double>? cpuCorePercent,
    List<HealthVolume>? volumes,
    List<HealthPhysicalDisk>? disks,
    this.hasMemoryCompressed = false,
    this.memoryCompressedBytes = 0,
    this.hasMemoryHardwareReserved = false,
    this.memoryHardwareReservedBytes = 0,
    this.hasMemoryPagedPool = false,
    this.memoryPagedPoolBytes = 0,
    this.hasMemoryNonpagedPool = false,
    this.memoryNonpagedPoolBytes = 0,
    this.hasMemoryPageFaultsPerSec = false,
    this.memoryPageFaultsPerSec = 0.0,
    this.hasGpuUtil3d = false,
    this.gpuUtil3d = 0.0,
    this.hasGpuUtilCompute = false,
    this.gpuUtilCompute = 0.0,
    this.hasGpuUtilCopy = false,
    this.gpuUtilCopy = 0.0,
    this.hasGpuUtilVideoDecode = false,
    this.gpuUtilVideoDecode = 0.0,
    this.hasGpuUtilVideoEncode = false,
    this.gpuUtilVideoEncode = 0.0,
    this.hasGpuUtilVideoProcessing = false,
    this.gpuUtilVideoProcessing = 0.0,
    this.hasGpuDedicatedUsed = false,
    this.gpuDedicatedUsedBytes = 0,
    this.hasGpuSharedUsed = false,
    this.gpuSharedUsedBytes = 0,
    this.hasGpuClockMhz = false,
    this.gpuClockMhz = 0.0,
    this.hasGpuMemoryClockMhz = false,
    this.gpuMemoryClockMhz = 0.0,
    this.hasGpuFanRpm = false,
    this.gpuFanRpm = 0.0,
    this.hasGpuPowerPercent = false,
    this.gpuPowerPercent = 0.0,
    this.hasNetPeakDownloadBps = false,
    this.netPeakDownloadBps = 0.0,
    this.hasNetPeakUploadBps = false,
    this.netPeakUploadBps = 0.0,
    this.hasNetAvgDownloadBps = false,
    this.netAvgDownloadBps = 0.0,
    this.hasNetAvgUploadBps = false,
    this.netAvgUploadBps = 0.0,
    this.hasNetUtilizationPercent = false,
    this.netUtilizationPercent = 0.0,
    this.hasNetConnectionMs = false,
    this.netConnectionMs = 0,
    this.hasNetBytesSent = false,
    this.netBytesSent = 0,
    this.hasNetBytesReceived = false,
    this.netBytesReceived = 0,
    this.hasNetPacketsSent = false,
    this.netPacketsSent = 0,
    this.hasNetPacketsReceived = false,
    this.netPacketsReceived = 0,
    this.hasNetErrors = false,
    this.netErrors = 0,
    this.hasNetDrops = false,
    this.netDrops = 0,
    this.netSsid = '',
    this.hasNetSignalPercent = false,
    this.netSignalPercent = 0.0,
    this.netWifiChannel = '',
    this.netWifiFrequency = '',
    this.netWifiSecurity = '',
  })  : topCpu = topCpu ?? <HealthProcessEntry>[],
        topMemory = topMemory ?? <HealthProcessEntry>[],
        topGpu = topGpu ?? <HealthProcessEntry>[],
        topDisk = topDisk ?? <HealthProcessEntry>[],
        topNetwork = topNetwork ?? <HealthProcessEntry>[],
        cpuCorePercent = cpuCorePercent ?? <double>[],
        volumes = volumes ?? <HealthVolume>[],
        disks = disks ?? <HealthPhysicalDisk>[];
  int unixMs;
  bool hasCpuPercent;
  double cpuPercent;
  int memoryUsedBytes;
  int memoryTotalBytes;
  bool hasGpuPercent;
  double gpuPercent;
  bool hasNetDownloadBps;
  double netDownloadBps;
  bool hasNetUploadBps;
  double netUploadBps;
  bool hasDiskReadBps;
  double diskReadBps;
  bool hasDiskWriteBps;
  double diskWriteBps;
  int diskUsedBytes;
  int diskTotalBytes;
  int uptimeMs;
  bool hasCpuTempC;
  double cpuTempC;
  bool hasGpuTempC;
  double gpuTempC;
  bool hasSsdTempC;
  double ssdTempC;
  bool hasCpuCurrentMhz;
  double cpuCurrentMhz;
  int memoryAvailableBytes;
  bool hasMemoryCommitted;
  int memoryCommittedBytes;
  int memoryCommitLimitBytes;
  bool hasMemoryCached;
  int memoryCachedBytes;
  String ipv4;
  String ipv6;
  String gateway;
  String dns;
  List<HealthProcessEntry> topCpu;
  List<HealthProcessEntry> topMemory;
  List<HealthProcessEntry> topGpu;
  List<HealthProcessEntry> topDisk;
  List<HealthProcessEntry> topNetwork;
  List<double> cpuCorePercent;
  List<HealthVolume> volumes;
  List<HealthPhysicalDisk> disks;
  bool hasMemoryCompressed;
  int memoryCompressedBytes;
  bool hasMemoryHardwareReserved;
  int memoryHardwareReservedBytes;
  bool hasMemoryPagedPool;
  int memoryPagedPoolBytes;
  bool hasMemoryNonpagedPool;
  int memoryNonpagedPoolBytes;
  bool hasMemoryPageFaultsPerSec;
  double memoryPageFaultsPerSec;
  bool hasGpuUtil3d;
  double gpuUtil3d;
  bool hasGpuUtilCompute;
  double gpuUtilCompute;
  bool hasGpuUtilCopy;
  double gpuUtilCopy;
  bool hasGpuUtilVideoDecode;
  double gpuUtilVideoDecode;
  bool hasGpuUtilVideoEncode;
  double gpuUtilVideoEncode;
  bool hasGpuUtilVideoProcessing;
  double gpuUtilVideoProcessing;
  bool hasGpuDedicatedUsed;
  int gpuDedicatedUsedBytes;
  bool hasGpuSharedUsed;
  int gpuSharedUsedBytes;
  bool hasGpuClockMhz;
  double gpuClockMhz;
  bool hasGpuMemoryClockMhz;
  double gpuMemoryClockMhz;
  bool hasGpuFanRpm;
  double gpuFanRpm;
  bool hasGpuPowerPercent;
  double gpuPowerPercent;
  bool hasNetPeakDownloadBps;
  double netPeakDownloadBps;
  bool hasNetPeakUploadBps;
  double netPeakUploadBps;
  bool hasNetAvgDownloadBps;
  double netAvgDownloadBps;
  bool hasNetAvgUploadBps;
  double netAvgUploadBps;
  bool hasNetUtilizationPercent;
  double netUtilizationPercent;
  bool hasNetConnectionMs;
  int netConnectionMs;
  bool hasNetBytesSent;
  int netBytesSent;
  bool hasNetBytesReceived;
  int netBytesReceived;
  bool hasNetPacketsSent;
  int netPacketsSent;
  bool hasNetPacketsReceived;
  int netPacketsReceived;
  bool hasNetErrors;
  int netErrors;
  bool hasNetDrops;
  int netDrops;
  String netSsid;
  bool hasNetSignalPercent;
  double netSignalPercent;
  String netWifiChannel;
  String netWifiFrequency;
  String netWifiSecurity;
}

class GetHealthSnapshot {
  GetHealthSnapshot();
}

class HealthSnapshot {
  HealthSnapshot({HealthStaticInfo? info, HealthSample? sample})
      : info = info ?? HealthStaticInfo(),
        sample = sample ?? HealthSample();
  HealthStaticInfo info;
  HealthSample sample;
}

class HealthUpdate {
  HealthUpdate({HealthSample? sample, this.processInventory})
    : sample = sample ?? HealthSample();
  HealthSample sample;
  HealthProcessInventoryUpdate? processInventory;
}

class StartHealthMonitoring {
  StartHealthMonitoring();
}

class StopHealthMonitoring {
  StopHealthMonitoring();
}

class GetDiagnosticsSnapshot {
  GetDiagnosticsSnapshot();
}

/// Pipeline stage health: 0 = healthy, 1 = warning, 2 = error.
class DiagnosticsSnapshot {
  DiagnosticsSnapshot({
    this.serviceVersion = '',
    this.protocolVersion = 0,
    this.serviceStartUnixMs = 0,
    this.serviceUptimeMs = 0,
    this.runMode = '',
    this.ipcListening = false,
    this.liveSubscribed = false,
    this.liveChannel = '',
    this.liveEventsPushed = 0,
    this.liveEventsDropped = 0,
    this.liveSubscriberReconnects = 0,
    this.lastLiveEventUnixMs = 0,
    this.lastLiveEventTitle = '',
    this.liveQueueDepth = 0,
    this.liveQueueCapacity = 0,
    this.ipcMessagesReceived = 0,
    this.ipcMessagesSent = 0,
    this.ipcErrors = 0,
    this.connectedClients = 0,
    this.servicePid = 0,
    this.hasCpuPercent = false,
    this.cpuPercent = 0.0,
    this.workingSetBytes = 0,
    this.threadCount = 0,
    this.handleCount = 0,
    this.stageEventLog = 0,
    this.stageCollector = 0,
    this.stageIntelligence = 0,
    this.stageIpc = 0,
    this.stageDetail = '',
    this.windowsEdition = '',
    this.windowsVersion = '',
  });
  String serviceVersion;
  int protocolVersion;
  int serviceStartUnixMs;
  int serviceUptimeMs;
  String runMode;
  bool ipcListening;

  bool liveSubscribed;
  String liveChannel;
  int liveEventsPushed;
  int liveEventsDropped;
  int liveSubscriberReconnects;
  int lastLiveEventUnixMs;
  String lastLiveEventTitle;
  int liveQueueDepth;
  int liveQueueCapacity;

  int ipcMessagesReceived;
  int ipcMessagesSent;
  int ipcErrors;
  int connectedClients;

  int servicePid;
  bool hasCpuPercent;
  double cpuPercent;
  int workingSetBytes;
  int threadCount;
  int handleCount;

  int stageEventLog;
  int stageCollector;
  int stageIntelligence;
  int stageIpc;
  String stageDetail;

  String windowsEdition;
  String windowsVersion;
}

class InjectDiagnosticsTestEvent {
  InjectDiagnosticsTestEvent();
}

class Envelope {
  Envelope({this.requestId = 0, this.body});
  int requestId;
  Object? body;
}

void _writeVarint(int value, BytesBuilder out) {
  var v = value;
  while (v >= 0x80) {
    out.addByte((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.addByte(v & 0x7f);
}

void _writeTag(int field, int wire, BytesBuilder out) {
  _writeVarint((field << 3) | wire, out);
}

void _writeString(int field, String s, BytesBuilder out) {
  final bytes = utf8.encode(s);
  _writeTag(field, 2, out);
  _writeVarint(bytes.length, out);
  out.add(bytes);
}

void _writeU64(int field, int v, BytesBuilder out) {
  _writeTag(field, 0, out);
  _writeVarint(v, out);
}

void _writeBool(int field, bool v, BytesBuilder out) {
  _writeU64(field, v ? 1 : 0, out);
}

void _writeDouble(int field, double v, BytesBuilder out) {
  _writeTag(field, 1, out);
  final bd = ByteData(8);
  bd.setFloat64(0, v, Endian.little);
  out.add(bd.buffer.asUint8List());
}

Uint8List _encodeClientHello(ClientHello m) {
  final out = BytesBuilder();
  _writeU64(1, m.protocolVersion, out);
  _writeString(2, m.clientName, out);
  _writeString(3, m.clientVersion, out);
  return out.toBytes();
}

Uint8List _encodeServerHello(ServerHello m) {
  final out = BytesBuilder();
  _writeU64(1, m.protocolVersion, out);
  _writeString(2, m.serviceVersion, out);
  return out.toBytes();
}

Uint8List _encodePing(Ping m) {
  final out = BytesBuilder();
  _writeU64(1, m.nonce, out);
  _writeU64(2, m.unixMs, out);
  return out.toBytes();
}

Uint8List _encodePong(Pong m) {
  final out = BytesBuilder();
  _writeU64(1, m.nonce, out);
  _writeU64(2, m.unixMs, out);
  _writeString(3, m.serviceVersion, out);
  return out.toBytes();
}

Uint8List _encodeHeartbeat(Heartbeat m) {
  final out = BytesBuilder();
  _writeU64(1, m.unixMs, out);
  return out.toBytes();
}

Uint8List _encodeError(ErrorResponse m) {
  final out = BytesBuilder();
  _writeU64(1, m.code, out);
  _writeString(2, m.message, out);
  _writeString(3, m.technicalDetail, out);
  _writeString(4, m.component, out);
  return out.toBytes();
}

Uint8List _encodeTimelineEvent(TimelineEvent m) {
  final out = BytesBuilder();
  _writeString(1, m.eventId, out);
  _writeU64(2, m.timestampUnixMs, out);
  _writeString(3, m.timestampIso, out);
  _writeU64(4, m.severity, out);
  _writeString(5, m.channel, out);
  _writeString(6, m.providerName, out);
  _writeU64(7, m.winEventId, out);
  _writeU64(8, m.recordId, out);
  _writeString(9, m.computerName, out);
  _writeString(10, m.summary, out);
  _writeString(11, m.technicalSummary, out);
  _writeString(12, m.message, out);
  _writeString(13, m.title, out);
  _writeString(14, m.recommendation, out);
  _writeU64(15, m.actionRequired ? 1 : 0, out);
  _writeU64(16, m.importance, out);
  _writeString(17, m.category, out);
  return out.toBytes();
}

Uint8List _encodeGetTimelineSnapshot(GetTimelineSnapshot m) {
  final out = BytesBuilder();
  _writeU64(1, m.limit, out);
  _writeString(2, m.channel, out);
  return out.toBytes();
}

Uint8List _encodeTimelineSnapshot(TimelineSnapshot m) {
  final out = BytesBuilder();
  for (final event in m.events) {
    _writeBytesField(1, _encodeTimelineEvent(event), out);
  }
  _writeString(2, m.channel, out);
  _writeU64(3, m.requestedLimit, out);
  _writeU64(4, m.collectedUnixMs, out);
  return out.toBytes();
}

Uint8List _encodeStartLiveMonitoring(StartLiveMonitoring m) {
  final out = BytesBuilder();
  _writeString(1, m.channel, out);
  return out.toBytes();
}

Uint8List _encodeStopLiveMonitoring(StopLiveMonitoring _) {
  return Uint8List(0);
}

Uint8List _encodeHealthProcessEntry(HealthProcessEntry m) {
  final out = BytesBuilder();
  _writeU64(1, m.pid, out);
  _writeString(2, m.name, out);
  _writeBool(3, m.hasCpuPercent, out);
  _writeDouble(4, m.cpuPercent, out);
  _writeBool(5, m.hasMemoryBytes, out);
  _writeU64(6, m.memoryBytes, out);
  _writeBool(7, m.hasGpuPercent, out);
  _writeDouble(8, m.gpuPercent, out);
  _writeBool(9, m.hasDiskBps, out);
  _writeDouble(10, m.diskBps, out);
  _writeBool(11, m.hasNetBps, out);
  _writeDouble(12, m.netBps, out);
  _writeString(13, m.path, out);
  _writeU64(14, m.threadCount, out);
  _writeU64(15, m.handleCount, out);
  _writeBool(16, m.hasCreateTime, out);
  _writeU64(17, m.createTimeUnixMs, out);
  _writeBool(18, m.hasIsCritical, out);
  _writeBool(19, m.isCritical, out);
  _writeBool(20, m.hasWorkingSetBytes, out);
  _writeU64(21, m.workingSetBytes, out);
  _writeBool(22, m.hasCommitBytes, out);
  _writeU64(23, m.commitBytes, out);
  _writeBool(24, m.hasPagedPoolBytes, out);
  _writeU64(25, m.pagedPoolBytes, out);
  _writeBool(26, m.hasNonpagedPoolBytes, out);
  _writeU64(27, m.nonpagedPoolBytes, out);
  _writeBool(28, m.hasGpuDedicatedBytes, out);
  _writeU64(29, m.gpuDedicatedBytes, out);
  _writeBool(30, m.hasGpuSharedBytes, out);
  _writeU64(31, m.gpuSharedBytes, out);
  _writeString(32, m.gpuEngine, out);
  return out.toBytes();
}

Uint8List _encodeHealthProcessInventoryUpdate(HealthProcessInventoryUpdate m) {
  final out = BytesBuilder();
  _writeU64(1, m.seq, out);
  _writeBool(2, m.fullResync, out);
  for (final e in m.upserts) {
    _writeBytesField(3, _encodeHealthProcessEntry(e), out);
  }
  for (final pid in m.removedPids) {
    _writeU64(4, pid, out);
  }
  return out.toBytes();
}

Uint8List _encodeGetProcessDetails(GetProcessDetails m) {
  final out = BytesBuilder();
  _writeU64(1, m.pid, out);
  return out.toBytes();
}

Uint8List _encodeProcessDetails(ProcessDetails m) {
  final out = BytesBuilder();
  _writeU64(1, m.pid, out);
  _writeString(2, m.name, out);
  _writeString(3, m.path, out);
  _writeString(4, m.company, out);
  _writeString(5, m.commandLine, out);
  _writeBool(6, m.hasCreateTime, out);
  _writeU64(7, m.createTimeUnixMs, out);
  _writeU64(8, m.threadCount, out);
  _writeU64(9, m.handleCount, out);
  _writeBool(10, m.hasPath, out);
  _writeBool(11, m.hasCompany, out);
  _writeBool(12, m.hasCommandLine, out);
  _writeU64(13, m.parentPid, out);
  _writeBool(14, m.hasParentPid, out);
  _writeString(15, m.parentName, out);
  _writeBool(16, m.hasParentName, out);
  _writeString(17, m.user, out);
  _writeBool(18, m.hasUser, out);
  _writeString(19, m.integrityLevel, out);
  _writeBool(20, m.hasIntegrityLevel, out);
  _writeBool(21, m.elevated, out);
  _writeBool(22, m.hasElevated, out);
  _writeString(23, m.architecture, out);
  _writeBool(24, m.hasArchitecture, out);
  _writeString(25, m.productName, out);
  _writeBool(26, m.hasProductName, out);
  return out.toBytes();
}

Uint8List _encodeHealthVolume(HealthVolume m) {
  final out = BytesBuilder();
  _writeString(1, m.id, out);
  _writeString(2, m.mountPoint, out);
  _writeString(3, m.label, out);
  _writeString(4, m.fileSystem, out);
  _writeU64(5, m.kind.index, out);
  _writeU64(6, m.usedBytes, out);
  _writeU64(7, m.totalBytes, out);
  _writeBool(8, m.hasCapacity, out);
  _writeBool(9, m.includedInSummary, out);
  return out.toBytes();
}

Uint8List _encodeHealthPhysicalDisk(HealthPhysicalDisk m) {
  final out = BytesBuilder();
  _writeString(1, m.id, out);
  _writeString(2, m.name, out);
  _writeBool(3, m.hasReadBps, out);
  _writeDouble(4, m.readBps, out);
  _writeBool(5, m.hasWriteBps, out);
  _writeDouble(6, m.writeBps, out);
  return out.toBytes();
}

Uint8List _encodeHealthStaticInfo(HealthStaticInfo m) {
  final out = BytesBuilder();
  _writeString(1, m.windowsEdition, out);
  _writeString(2, m.windowsVersion, out);
  _writeString(3, m.cpuModel, out);
  _writeString(4, m.gpuModel, out);
  _writeU64(5, m.installedRamBytes, out);
  _writeU64(6, m.primaryStorageBytes, out);
  _writeString(7, m.activeNetworkAdapter, out);
  _writeU64(8, m.cpuBaseMhz, out);
  _writeU64(9, m.cpuSockets, out);
  _writeU64(10, m.cpuCores, out);
  _writeU64(11, m.cpuLogicalProcessors, out);
  _writeBool(12, m.cpuVirtualizationEnabled, out);
  _writeU64(13, m.gpuDedicatedBytes, out);
  _writeU64(14, m.gpuSharedBytes, out);
  _writeString(15, m.cpuArchitecture, out);
  _writeString(16, m.cpuInstructionSet, out);
  _writeU64(17, m.cpuNumaNodes, out);
  _writeBool(18, m.hasCpuSmt, out);
  _writeBool(19, m.cpuSmtEnabled, out);
  _writeBool(20, m.hasCpuL1Cache, out);
  _writeU64(21, m.cpuL1CacheBytes, out);
  _writeBool(22, m.hasCpuL2Cache, out);
  _writeU64(23, m.cpuL2CacheBytes, out);
  _writeBool(24, m.hasCpuL3Cache, out);
  _writeU64(25, m.cpuL3CacheBytes, out);
  _writeString(26, m.cpuVirtualizationVendor, out);
  _writeString(27, m.gpuVendor, out);
  _writeString(28, m.gpuDriverVersion, out);
  _writeString(29, m.gpuDriverDate, out);
  _writeBool(30, m.hasGpuLuid, out);
  _writeU64(31, m.gpuLuidHigh, out);
  _writeU64(32, m.gpuLuidLow, out);
  _writeString(33, m.gpuDirectxVersion, out);
  _writeString(34, m.gpuWddmVersion, out);
  _writeBool(35, m.hasGpuHardwareScheduling, out);
  _writeBool(36, m.gpuHardwareScheduling, out);
  _writeString(37, m.gpuPcieLinkSpeed, out);
  _writeString(38, m.gpuPcieLinkWidth, out);
  _writeString(39, m.netManufacturer, out);
  _writeString(40, m.netDescription, out);
  _writeString(41, m.netMacAddress, out);
  _writeString(42, m.netDriverVersion, out);
  _writeString(43, m.netDriverDate, out);
  _writeString(44, m.netConnectionType, out);
  _writeString(45, m.netDuplex, out);
  _writeBool(46, m.hasNetMtu, out);
  _writeU64(47, m.netMtu, out);
  _writeBool(48, m.hasNetIfIndex, out);
  _writeU64(49, m.netIfIndex, out);
  _writeBool(50, m.hasNetLinkSpeedBps, out);
  _writeU64(51, m.netLinkSpeedBps, out);
  _writeBool(52, m.hasNetDhcp, out);
  _writeBool(53, m.netDhcpEnabled, out);
  _writeString(54, m.netDhcpServer, out);
  _writeBool(55, m.hasNetLeaseObtained, out);
  _writeU64(56, m.netLeaseObtainedUnixMs, out);
  _writeBool(57, m.hasNetLeaseExpires, out);
  _writeU64(58, m.netLeaseExpiresUnixMs, out);
  _writeBool(59, m.hasMemSlotsUsed, out);
  _writeU64(60, m.memSlotsUsed, out);
  _writeBool(61, m.hasMemModuleCount, out);
  _writeU64(62, m.memModuleCount, out);
  _writeString(63, m.memDdrGeneration, out);
  _writeBool(64, m.hasMemSpeedMhz, out);
  _writeU64(65, m.memSpeedMhz, out);
  _writeString(66, m.memFormFactor, out);
  _writeBool(67, m.hasMemEcc, out);
  _writeBool(68, m.memEcc, out);
  _writeBool(69, m.hasMemChannels, out);
  _writeU64(70, m.memChannels, out);
  _writeString(71, m.memDimmVendor, out);
  _writeString(72, m.memDimmPartNumber, out);
  _writeString(73, m.memDimmSerial, out);
  _writeString(74, m.diskInterface, out);
  _writeString(75, m.diskBus, out);
  _writeString(76, m.diskModel, out);
  _writeString(77, m.diskSerial, out);
  _writeString(78, m.diskFirmware, out);
  _writeString(79, m.diskPartitionStyle, out);
  _writeBool(80, m.hasDiskSectorSize, out);
  _writeU64(81, m.diskSectorSize, out);
  _writeBool(82, m.hasDiskRotationRate, out);
  _writeU64(83, m.diskRotationRate, out);
  _writeBool(84, m.hasDiskTrim, out);
  _writeBool(85, m.diskTrimSupported, out);
  _writeString(86, m.gpuPciLocation, out);
  _writeBool(87, m.hasGpuResizableBar, out);
  _writeBool(88, m.gpuResizableBar, out);
  return out.toBytes();
}

Uint8List _encodeHealthSample(HealthSample m) {
  final out = BytesBuilder();
  _writeU64(1, m.unixMs, out);
  _writeBool(2, m.hasCpuPercent, out);
  _writeDouble(3, m.cpuPercent, out);
  _writeU64(4, m.memoryUsedBytes, out);
  _writeU64(5, m.memoryTotalBytes, out);
  _writeBool(6, m.hasGpuPercent, out);
  _writeDouble(7, m.gpuPercent, out);
  _writeBool(8, m.hasNetDownloadBps, out);
  _writeDouble(9, m.netDownloadBps, out);
  _writeBool(10, m.hasNetUploadBps, out);
  _writeDouble(11, m.netUploadBps, out);
  _writeBool(12, m.hasDiskReadBps, out);
  _writeDouble(13, m.diskReadBps, out);
  _writeBool(14, m.hasDiskWriteBps, out);
  _writeDouble(15, m.diskWriteBps, out);
  _writeU64(16, m.diskUsedBytes, out);
  _writeU64(17, m.diskTotalBytes, out);
  _writeU64(18, m.uptimeMs, out);
  _writeBool(19, m.hasCpuTempC, out);
  _writeDouble(20, m.cpuTempC, out);
  _writeBool(21, m.hasGpuTempC, out);
  _writeDouble(22, m.gpuTempC, out);
  _writeBool(23, m.hasSsdTempC, out);
  _writeDouble(24, m.ssdTempC, out);
  _writeBool(25, m.hasCpuCurrentMhz, out);
  _writeDouble(26, m.cpuCurrentMhz, out);
  _writeU64(27, m.memoryAvailableBytes, out);
  _writeBool(28, m.hasMemoryCommitted, out);
  _writeU64(29, m.memoryCommittedBytes, out);
  _writeU64(30, m.memoryCommitLimitBytes, out);
  _writeBool(31, m.hasMemoryCached, out);
  _writeU64(32, m.memoryCachedBytes, out);
  _writeString(33, m.ipv4, out);
  _writeString(34, m.ipv6, out);
  _writeString(35, m.gateway, out);
  _writeString(36, m.dns, out);
  for (final e in m.topCpu) {
    _writeBytesField(37, _encodeHealthProcessEntry(e), out);
  }
  for (final e in m.topMemory) {
    _writeBytesField(38, _encodeHealthProcessEntry(e), out);
  }
  for (final e in m.topGpu) {
    _writeBytesField(39, _encodeHealthProcessEntry(e), out);
  }
  for (final e in m.topDisk) {
    _writeBytesField(40, _encodeHealthProcessEntry(e), out);
  }
  for (final e in m.topNetwork) {
    _writeBytesField(41, _encodeHealthProcessEntry(e), out);
  }
  for (final core in m.cpuCorePercent) {
    _writeDouble(42, core, out);
  }
  for (final v in m.volumes) {
    _writeBytesField(43, _encodeHealthVolume(v), out);
  }
  for (final d in m.disks) {
    _writeBytesField(44, _encodeHealthPhysicalDisk(d), out);
  }
  _writeBool(45, m.hasMemoryCompressed, out);
  _writeU64(46, m.memoryCompressedBytes, out);
  _writeBool(47, m.hasMemoryHardwareReserved, out);
  _writeU64(48, m.memoryHardwareReservedBytes, out);
  _writeBool(49, m.hasMemoryPagedPool, out);
  _writeU64(50, m.memoryPagedPoolBytes, out);
  _writeBool(51, m.hasMemoryNonpagedPool, out);
  _writeU64(52, m.memoryNonpagedPoolBytes, out);
  _writeBool(53, m.hasMemoryPageFaultsPerSec, out);
  _writeDouble(54, m.memoryPageFaultsPerSec, out);
  _writeBool(55, m.hasGpuUtil3d, out);
  _writeDouble(56, m.gpuUtil3d, out);
  _writeBool(57, m.hasGpuUtilCompute, out);
  _writeDouble(58, m.gpuUtilCompute, out);
  _writeBool(59, m.hasGpuUtilCopy, out);
  _writeDouble(60, m.gpuUtilCopy, out);
  _writeBool(61, m.hasGpuUtilVideoDecode, out);
  _writeDouble(62, m.gpuUtilVideoDecode, out);
  _writeBool(63, m.hasGpuUtilVideoEncode, out);
  _writeDouble(64, m.gpuUtilVideoEncode, out);
  _writeBool(65, m.hasGpuDedicatedUsed, out);
  _writeU64(66, m.gpuDedicatedUsedBytes, out);
  _writeBool(67, m.hasGpuSharedUsed, out);
  _writeU64(68, m.gpuSharedUsedBytes, out);
  _writeBool(69, m.hasGpuClockMhz, out);
  _writeDouble(70, m.gpuClockMhz, out);
  _writeBool(71, m.hasGpuMemoryClockMhz, out);
  _writeDouble(72, m.gpuMemoryClockMhz, out);
  _writeBool(73, m.hasGpuFanRpm, out);
  _writeDouble(74, m.gpuFanRpm, out);
  _writeBool(75, m.hasGpuPowerPercent, out);
  _writeDouble(76, m.gpuPowerPercent, out);
  _writeBool(77, m.hasNetPeakDownloadBps, out);
  _writeDouble(78, m.netPeakDownloadBps, out);
  _writeBool(79, m.hasNetPeakUploadBps, out);
  _writeDouble(80, m.netPeakUploadBps, out);
  _writeBool(81, m.hasNetAvgDownloadBps, out);
  _writeDouble(82, m.netAvgDownloadBps, out);
  _writeBool(83, m.hasNetAvgUploadBps, out);
  _writeDouble(84, m.netAvgUploadBps, out);
  _writeBool(85, m.hasNetUtilizationPercent, out);
  _writeDouble(86, m.netUtilizationPercent, out);
  _writeBool(87, m.hasNetConnectionMs, out);
  _writeU64(88, m.netConnectionMs, out);
  _writeBool(89, m.hasNetBytesSent, out);
  _writeU64(90, m.netBytesSent, out);
  _writeBool(91, m.hasNetBytesReceived, out);
  _writeU64(92, m.netBytesReceived, out);
  _writeBool(93, m.hasNetPacketsSent, out);
  _writeU64(94, m.netPacketsSent, out);
  _writeBool(95, m.hasNetPacketsReceived, out);
  _writeU64(96, m.netPacketsReceived, out);
  _writeBool(97, m.hasNetErrors, out);
  _writeU64(98, m.netErrors, out);
  _writeBool(99, m.hasNetDrops, out);
  _writeU64(100, m.netDrops, out);
  _writeString(101, m.netSsid, out);
  _writeBool(102, m.hasNetSignalPercent, out);
  _writeDouble(103, m.netSignalPercent, out);
  _writeString(104, m.netWifiChannel, out);
  _writeString(105, m.netWifiFrequency, out);
  _writeString(106, m.netWifiSecurity, out);
  _writeBool(107, m.hasGpuUtilVideoProcessing, out);
  _writeDouble(108, m.gpuUtilVideoProcessing, out);
  return out.toBytes();
}

Uint8List _encodeGetHealthSnapshot(GetHealthSnapshot _) {
  return Uint8List(0);
}

Uint8List _encodeHealthSnapshot(HealthSnapshot m) {
  final out = BytesBuilder();
  _writeBytesField(1, _encodeHealthStaticInfo(m.info), out);
  _writeBytesField(2, _encodeHealthSample(m.sample), out);
  return out.toBytes();
}

Uint8List _encodeHealthUpdate(HealthUpdate m) {
  final out = BytesBuilder();
  _writeBytesField(1, _encodeHealthSample(m.sample), out);
  final processInventory = m.processInventory;
  if (processInventory != null) {
    _writeBytesField(
      2,
      _encodeHealthProcessInventoryUpdate(processInventory),
      out,
    );
  }
  return out.toBytes();
}

Uint8List _encodeStartHealthMonitoring(StartHealthMonitoring _) {
  return Uint8List(0);
}

Uint8List _encodeStopHealthMonitoring(StopHealthMonitoring _) {
  return Uint8List(0);
}

Uint8List _encodeGetDiagnosticsSnapshot(GetDiagnosticsSnapshot _) {
  return Uint8List(0);
}

Uint8List _encodeDiagnosticsSnapshot(DiagnosticsSnapshot m) {
  final out = BytesBuilder();
  _writeString(1, m.serviceVersion, out);
  _writeU64(2, m.protocolVersion, out);
  _writeU64(3, m.serviceStartUnixMs, out);
  _writeU64(4, m.serviceUptimeMs, out);
  _writeString(5, m.runMode, out);
  _writeBool(6, m.ipcListening, out);

  _writeBool(7, m.liveSubscribed, out);
  _writeString(8, m.liveChannel, out);
  _writeU64(9, m.liveEventsPushed, out);
  _writeU64(10, m.liveEventsDropped, out);
  _writeU64(11, m.liveSubscriberReconnects, out);
  _writeU64(12, m.lastLiveEventUnixMs, out);
  _writeString(13, m.lastLiveEventTitle, out);
  _writeU64(14, m.liveQueueDepth, out);
  _writeU64(15, m.liveQueueCapacity, out);

  _writeU64(16, m.ipcMessagesReceived, out);
  _writeU64(17, m.ipcMessagesSent, out);
  _writeU64(18, m.ipcErrors, out);
  _writeU64(19, m.connectedClients, out);

  _writeU64(20, m.servicePid, out);
  _writeBool(21, m.hasCpuPercent, out);
  _writeDouble(22, m.cpuPercent, out);
  _writeU64(23, m.workingSetBytes, out);
  _writeU64(24, m.threadCount, out);
  _writeU64(25, m.handleCount, out);

  _writeU64(26, m.stageEventLog, out);
  _writeU64(27, m.stageCollector, out);
  _writeU64(28, m.stageIntelligence, out);
  _writeU64(29, m.stageIpc, out);
  _writeString(30, m.stageDetail, out);

  _writeString(31, m.windowsEdition, out);
  _writeString(32, m.windowsVersion, out);
  return out.toBytes();
}

Uint8List _encodeInjectDiagnosticsTestEvent(InjectDiagnosticsTestEvent _) {
  return Uint8List(0);
}

void _writeBytesField(int field, Uint8List bytes, BytesBuilder out) {
  _writeTag(field, 2, out);
  _writeVarint(bytes.length, out);
  out.add(bytes);
}

Uint8List encodeEnvelope(Envelope env) {
  final out = BytesBuilder();
  _writeU64(1, env.requestId, out);
  final body = env.body;
  if (body is ClientHello) {
    _writeBytesField(10, _encodeClientHello(body), out);
  } else if (body is ServerHello) {
    _writeBytesField(11, _encodeServerHello(body), out);
  } else if (body is Ping) {
    _writeBytesField(12, _encodePing(body), out);
  } else if (body is Pong) {
    _writeBytesField(13, _encodePong(body), out);
  } else if (body is Heartbeat) {
    _writeBytesField(14, _encodeHeartbeat(body), out);
  } else if (body is GetTimelineSnapshot) {
    _writeBytesField(20, _encodeGetTimelineSnapshot(body), out);
  } else if (body is TimelineSnapshot) {
    _writeBytesField(21, _encodeTimelineSnapshot(body), out);
  } else if (body is TimelineEvent) {
    _writeBytesField(22, _encodeTimelineEvent(body), out);
  } else if (body is StartLiveMonitoring) {
    _writeBytesField(23, _encodeStartLiveMonitoring(body), out);
  } else if (body is StopLiveMonitoring) {
    _writeBytesField(24, _encodeStopLiveMonitoring(body), out);
  } else if (body is GetHealthSnapshot) {
    _writeBytesField(25, _encodeGetHealthSnapshot(body), out);
  } else if (body is HealthSnapshot) {
    _writeBytesField(26, _encodeHealthSnapshot(body), out);
  } else if (body is HealthUpdate) {
    _writeBytesField(27, _encodeHealthUpdate(body), out);
  } else if (body is StartHealthMonitoring) {
    _writeBytesField(28, _encodeStartHealthMonitoring(body), out);
  } else if (body is StopHealthMonitoring) {
    _writeBytesField(29, _encodeStopHealthMonitoring(body), out);
  } else if (body is GetDiagnosticsSnapshot) {
    _writeBytesField(30, _encodeGetDiagnosticsSnapshot(body), out);
  } else if (body is DiagnosticsSnapshot) {
    _writeBytesField(31, _encodeDiagnosticsSnapshot(body), out);
  } else if (body is InjectDiagnosticsTestEvent) {
    _writeBytesField(32, _encodeInjectDiagnosticsTestEvent(body), out);
  } else if (body is GetProcessDetails) {
    _writeBytesField(33, _encodeGetProcessDetails(body), out);
  } else if (body is ProcessDetails) {
    _writeBytesField(34, _encodeProcessDetails(body), out);
  } else if (body is ErrorResponse) {
    _writeBytesField(99, _encodeError(body), out);
  }
  return out.toBytes();
}

class _Reader {
  _Reader(this.data) : offset = 0;
  final Uint8List data;
  int offset;

  bool get hasMore => offset < data.length;

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (offset < data.length) {
      final b = data[offset++];
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
    }
    throw FormatException('truncated varint');
  }

  String readString() {
    final len = readVarint();
    if (len < 0 || offset + len > data.length) {
      throw FormatException('truncated string');
    }
    final bytes = data.sublist(offset, offset + len);
    offset += len;
    // Event Log text may contain legacy encodings; never fail the whole frame.
    return utf8.decode(bytes, allowMalformed: true);
  }

  Uint8List readBytes() {
    final len = readVarint();
    final bytes = data.sublist(offset, offset + len);
    offset += len;
    return bytes;
  }

  double readDouble() {
    if (offset + 8 > data.length) {
      throw FormatException('truncated double');
    }
    final bd = ByteData.sublistView(data, offset, offset + 8);
    offset += 8;
    return bd.getFloat64(0, Endian.little);
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        readVarint();
        break;
      case 1:
        offset += 8;
        break;
      case 2:
        final len = readVarint();
        offset += len;
        break;
      case 5:
        offset += 4;
        break;
      default:
        throw FormatException('unknown wire $wire');
    }
  }
}

ClientHello _decodeClientHello(Uint8List data) {
  final r = _Reader(data);
  final m = ClientHello();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.protocolVersion = r.readVarint();
    } else if (field == 2 && wire == 2) {
      m.clientName = r.readString();
    } else if (field == 3 && wire == 2) {
      m.clientVersion = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

ServerHello _decodeServerHello(Uint8List data) {
  final r = _Reader(data);
  final m = ServerHello();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.protocolVersion = r.readVarint();
    } else if (field == 2 && wire == 2) {
      m.serviceVersion = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

Ping _decodePing(Uint8List data) {
  final r = _Reader(data);
  final m = Ping();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.nonce = r.readVarint();
    } else if (field == 2 && wire == 0) {
      m.unixMs = r.readVarint();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

Pong _decodePong(Uint8List data) {
  final r = _Reader(data);
  final m = Pong();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.nonce = r.readVarint();
    } else if (field == 2 && wire == 0) {
      m.unixMs = r.readVarint();
    } else if (field == 3 && wire == 2) {
      m.serviceVersion = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

Heartbeat _decodeHeartbeat(Uint8List data) {
  final r = _Reader(data);
  final m = Heartbeat();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.unixMs = r.readVarint();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

ErrorResponse _decodeError(Uint8List data) {
  final r = _Reader(data);
  final m = ErrorResponse();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.code = r.readVarint();
    } else if (field == 2 && wire == 2) {
      m.message = r.readString();
    } else if (field == 3 && wire == 2) {
      m.technicalDetail = r.readString();
    } else if (field == 4 && wire == 2) {
      m.component = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

TimelineEvent _decodeTimelineEvent(Uint8List data) {
  final r = _Reader(data);
  final m = TimelineEvent();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      m.eventId = r.readString();
    } else if (field == 2 && wire == 0) {
      m.timestampUnixMs = r.readVarint();
    } else if (field == 3 && wire == 2) {
      m.timestampIso = r.readString();
    } else if (field == 4 && wire == 0) {
      m.severity = r.readVarint();
    } else if (field == 5 && wire == 2) {
      m.channel = r.readString();
    } else if (field == 6 && wire == 2) {
      m.providerName = r.readString();
    } else if (field == 7 && wire == 0) {
      m.winEventId = r.readVarint();
    } else if (field == 8 && wire == 0) {
      m.recordId = r.readVarint();
    } else if (field == 9 && wire == 2) {
      m.computerName = r.readString();
    } else if (field == 10 && wire == 2) {
      m.summary = r.readString();
    } else if (field == 11 && wire == 2) {
      m.technicalSummary = r.readString();
    } else if (field == 12 && wire == 2) {
      m.message = r.readString();
    } else if (field == 13 && wire == 2) {
      m.title = r.readString();
    } else if (field == 14 && wire == 2) {
      m.recommendation = r.readString();
    } else if (field == 15 && wire == 0) {
      m.actionRequired = r.readVarint() != 0;
    } else if (field == 16 && wire == 0) {
      m.importance = r.readVarint();
    } else if (field == 17 && wire == 2) {
      m.category = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

GetTimelineSnapshot _decodeGetTimelineSnapshot(Uint8List data) {
  final r = _Reader(data);
  final m = GetTimelineSnapshot();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.limit = r.readVarint();
    } else if (field == 2 && wire == 2) {
      m.channel = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

TimelineSnapshot _decodeTimelineSnapshot(Uint8List data) {
  final r = _Reader(data);
  final m = TimelineSnapshot();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      final sub = r.readBytes();
      m.events.add(_decodeTimelineEvent(sub));
    } else if (field == 2 && wire == 2) {
      m.channel = r.readString();
    } else if (field == 3 && wire == 0) {
      m.requestedLimit = r.readVarint();
    } else if (field == 4 && wire == 0) {
      m.collectedUnixMs = r.readVarint();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

StartLiveMonitoring _decodeStartLiveMonitoring(Uint8List data) {
  final r = _Reader(data);
  final m = StartLiveMonitoring();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      m.channel = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

StopLiveMonitoring _decodeStopLiveMonitoring(Uint8List data) {
  final r = _Reader(data);
  while (r.hasMore) {
    final tag = r.readVarint();
    final wire = tag & 7;
    r.skip(wire);
  }
  return StopLiveMonitoring();
}

HealthProcessEntry _decodeHealthProcessEntry(Uint8List data) {
  final r = _Reader(data);
  final m = HealthProcessEntry();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.pid = r.readVarint();
    } else if (field == 2 && wire == 2) {
      m.name = r.readString();
    } else if (field == 3 && wire == 0) {
      m.hasCpuPercent = r.readVarint() != 0;
    } else if (field == 4 && wire == 1) {
      m.cpuPercent = r.readDouble();
    } else if (field == 5 && wire == 0) {
      m.hasMemoryBytes = r.readVarint() != 0;
    } else if (field == 6 && wire == 0) {
      m.memoryBytes = r.readVarint();
    } else if (field == 7 && wire == 0) {
      m.hasGpuPercent = r.readVarint() != 0;
    } else if (field == 8 && wire == 1) {
      m.gpuPercent = r.readDouble();
    } else if (field == 9 && wire == 0) {
      m.hasDiskBps = r.readVarint() != 0;
    } else if (field == 10 && wire == 1) {
      m.diskBps = r.readDouble();
    } else if (field == 11 && wire == 0) {
      m.hasNetBps = r.readVarint() != 0;
    } else if (field == 12 && wire == 1) {
      m.netBps = r.readDouble();
    } else if (field == 13 && wire == 2) {
      m.path = r.readString();
    } else if (field == 14 && wire == 0) {
      m.threadCount = r.readVarint();
    } else if (field == 15 && wire == 0) {
      m.handleCount = r.readVarint();
    } else if (field == 16 && wire == 0) {
      m.hasCreateTime = r.readVarint() != 0;
    } else if (field == 17 && wire == 0) {
      m.createTimeUnixMs = r.readVarint();
    } else if (field == 18 && wire == 0) {
      m.hasIsCritical = r.readVarint() != 0;
    } else if (field == 19 && wire == 0) {
      m.isCritical = r.readVarint() != 0;
    } else if (field == 20 && wire == 0) {
      m.hasWorkingSetBytes = r.readVarint() != 0;
    } else if (field == 21 && wire == 0) {
      m.workingSetBytes = r.readVarint();
    } else if (field == 22 && wire == 0) {
      m.hasCommitBytes = r.readVarint() != 0;
    } else if (field == 23 && wire == 0) {
      m.commitBytes = r.readVarint();
    } else if (field == 24 && wire == 0) {
      m.hasPagedPoolBytes = r.readVarint() != 0;
    } else if (field == 25 && wire == 0) {
      m.pagedPoolBytes = r.readVarint();
    } else if (field == 26 && wire == 0) {
      m.hasNonpagedPoolBytes = r.readVarint() != 0;
    } else if (field == 27 && wire == 0) {
      m.nonpagedPoolBytes = r.readVarint();
    } else if (field == 28 && wire == 0) {
      m.hasGpuDedicatedBytes = r.readVarint() != 0;
    } else if (field == 29 && wire == 0) {
      m.gpuDedicatedBytes = r.readVarint();
    } else if (field == 30 && wire == 0) {
      m.hasGpuSharedBytes = r.readVarint() != 0;
    } else if (field == 31 && wire == 0) {
      m.gpuSharedBytes = r.readVarint();
    } else if (field == 32 && wire == 2) {
      m.gpuEngine = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

HealthProcessInventoryUpdate _decodeHealthProcessInventoryUpdate(
  Uint8List data,
) {
  final r = _Reader(data);
  final m = HealthProcessInventoryUpdate();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.seq = r.readVarint();
    } else if (field == 2 && wire == 0) {
      m.fullResync = r.readVarint() != 0;
    } else if (field == 3 && wire == 2) {
      m.upserts.add(_decodeHealthProcessEntry(r.readBytes()));
    } else if (field == 4 && wire == 0) {
      m.removedPids.add(r.readVarint());
    } else {
      r.skip(wire);
    }
  }
  return m;
}

GetProcessDetails _decodeGetProcessDetails(Uint8List data) {
  final r = _Reader(data);
  final m = GetProcessDetails();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.pid = r.readVarint();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

ProcessDetails _decodeProcessDetails(Uint8List data) {
  final r = _Reader(data);
  final m = ProcessDetails();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.pid = r.readVarint();
    } else if (field == 2 && wire == 2) {
      m.name = r.readString();
    } else if (field == 3 && wire == 2) {
      m.path = r.readString();
    } else if (field == 4 && wire == 2) {
      m.company = r.readString();
    } else if (field == 5 && wire == 2) {
      m.commandLine = r.readString();
    } else if (field == 6 && wire == 0) {
      m.hasCreateTime = r.readVarint() != 0;
    } else if (field == 7 && wire == 0) {
      m.createTimeUnixMs = r.readVarint();
    } else if (field == 8 && wire == 0) {
      m.threadCount = r.readVarint();
    } else if (field == 9 && wire == 0) {
      m.handleCount = r.readVarint();
    } else if (field == 10 && wire == 0) {
      m.hasPath = r.readVarint() != 0;
    } else if (field == 11 && wire == 0) {
      m.hasCompany = r.readVarint() != 0;
    } else if (field == 12 && wire == 0) {
      m.hasCommandLine = r.readVarint() != 0;
    } else if (field == 13 && wire == 0) {
      m.parentPid = r.readVarint();
    } else if (field == 14 && wire == 0) {
      m.hasParentPid = r.readVarint() != 0;
    } else if (field == 15 && wire == 2) {
      m.parentName = r.readString();
    } else if (field == 16 && wire == 0) {
      m.hasParentName = r.readVarint() != 0;
    } else if (field == 17 && wire == 2) {
      m.user = r.readString();
    } else if (field == 18 && wire == 0) {
      m.hasUser = r.readVarint() != 0;
    } else if (field == 19 && wire == 2) {
      m.integrityLevel = r.readString();
    } else if (field == 20 && wire == 0) {
      m.hasIntegrityLevel = r.readVarint() != 0;
    } else if (field == 21 && wire == 0) {
      m.elevated = r.readVarint() != 0;
    } else if (field == 22 && wire == 0) {
      m.hasElevated = r.readVarint() != 0;
    } else if (field == 23 && wire == 2) {
      m.architecture = r.readString();
    } else if (field == 24 && wire == 0) {
      m.hasArchitecture = r.readVarint() != 0;
    } else if (field == 25 && wire == 2) {
      m.productName = r.readString();
    } else if (field == 26 && wire == 0) {
      m.hasProductName = r.readVarint() != 0;
    } else {
      r.skip(wire);
    }
  }
  return m;
}

HealthVolume _decodeHealthVolume(Uint8List data) {
  final r = _Reader(data);
  final m = HealthVolume();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      m.id = r.readString();
    } else if (field == 2 && wire == 2) {
      m.mountPoint = r.readString();
    } else if (field == 3 && wire == 2) {
      m.label = r.readString();
    } else if (field == 4 && wire == 2) {
      m.fileSystem = r.readString();
    } else if (field == 5 && wire == 0) {
      m.kind = healthDriveKindFromWire(r.readVarint());
    } else if (field == 6 && wire == 0) {
      m.usedBytes = r.readVarint();
    } else if (field == 7 && wire == 0) {
      m.totalBytes = r.readVarint();
    } else if (field == 8 && wire == 0) {
      m.hasCapacity = r.readVarint() != 0;
    } else if (field == 9 && wire == 0) {
      m.includedInSummary = r.readVarint() != 0;
    } else {
      r.skip(wire);
    }
  }
  return m;
}

HealthPhysicalDisk _decodeHealthPhysicalDisk(Uint8List data) {
  final r = _Reader(data);
  final m = HealthPhysicalDisk();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      m.id = r.readString();
    } else if (field == 2 && wire == 2) {
      m.name = r.readString();
    } else if (field == 3 && wire == 0) {
      m.hasReadBps = r.readVarint() != 0;
    } else if (field == 4 && wire == 1) {
      m.readBps = r.readDouble();
    } else if (field == 5 && wire == 0) {
      m.hasWriteBps = r.readVarint() != 0;
    } else if (field == 6 && wire == 1) {
      m.writeBps = r.readDouble();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

HealthStaticInfo _decodeHealthStaticInfo(Uint8List data) {
  final r = _Reader(data);
  final m = HealthStaticInfo();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      m.windowsEdition = r.readString();
    } else if (field == 2 && wire == 2) {
      m.windowsVersion = r.readString();
    } else if (field == 3 && wire == 2) {
      m.cpuModel = r.readString();
    } else if (field == 4 && wire == 2) {
      m.gpuModel = r.readString();
    } else if (field == 5 && wire == 0) {
      m.installedRamBytes = r.readVarint();
    } else if (field == 6 && wire == 0) {
      m.primaryStorageBytes = r.readVarint();
    } else if (field == 7 && wire == 2) {
      m.activeNetworkAdapter = r.readString();
    } else if (field == 8 && wire == 0) {
      m.cpuBaseMhz = r.readVarint();
    } else if (field == 9 && wire == 0) {
      m.cpuSockets = r.readVarint();
    } else if (field == 10 && wire == 0) {
      m.cpuCores = r.readVarint();
    } else if (field == 11 && wire == 0) {
      m.cpuLogicalProcessors = r.readVarint();
    } else if (field == 12 && wire == 0) {
      m.cpuVirtualizationEnabled = r.readVarint() != 0;
    } else if (field == 13 && wire == 0) {
      m.gpuDedicatedBytes = r.readVarint();
    } else if (field == 14 && wire == 0) {
      m.gpuSharedBytes = r.readVarint();
    } else if (field == 15 && wire == 2) {
      m.cpuArchitecture = r.readString();
    } else if (field == 16 && wire == 2) {
      m.cpuInstructionSet = r.readString();
    } else if (field == 17 && wire == 0) {
      m.cpuNumaNodes = r.readVarint();
    } else if (field == 18 && wire == 0) {
      m.hasCpuSmt = r.readVarint() != 0;
    } else if (field == 19 && wire == 0) {
      m.cpuSmtEnabled = r.readVarint() != 0;
    } else if (field == 20 && wire == 0) {
      m.hasCpuL1Cache = r.readVarint() != 0;
    } else if (field == 21 && wire == 0) {
      m.cpuL1CacheBytes = r.readVarint();
    } else if (field == 22 && wire == 0) {
      m.hasCpuL2Cache = r.readVarint() != 0;
    } else if (field == 23 && wire == 0) {
      m.cpuL2CacheBytes = r.readVarint();
    } else if (field == 24 && wire == 0) {
      m.hasCpuL3Cache = r.readVarint() != 0;
    } else if (field == 25 && wire == 0) {
      m.cpuL3CacheBytes = r.readVarint();
    } else if (field == 26 && wire == 2) {
      m.cpuVirtualizationVendor = r.readString();
    } else if (field == 27 && wire == 2) {
      m.gpuVendor = r.readString();
    } else if (field == 28 && wire == 2) {
      m.gpuDriverVersion = r.readString();
    } else if (field == 29 && wire == 2) {
      m.gpuDriverDate = r.readString();
    } else if (field == 30 && wire == 0) {
      m.hasGpuLuid = r.readVarint() != 0;
    } else if (field == 31 && wire == 0) {
      m.gpuLuidHigh = r.readVarint();
    } else if (field == 32 && wire == 0) {
      m.gpuLuidLow = r.readVarint();
    } else if (field == 33 && wire == 2) {
      m.gpuDirectxVersion = r.readString();
    } else if (field == 34 && wire == 2) {
      m.gpuWddmVersion = r.readString();
    } else if (field == 35 && wire == 0) {
      m.hasGpuHardwareScheduling = r.readVarint() != 0;
    } else if (field == 36 && wire == 0) {
      m.gpuHardwareScheduling = r.readVarint() != 0;
    } else if (field == 37 && wire == 2) {
      m.gpuPcieLinkSpeed = r.readString();
    } else if (field == 38 && wire == 2) {
      m.gpuPcieLinkWidth = r.readString();
    } else if (field == 39 && wire == 2) {
      m.netManufacturer = r.readString();
    } else if (field == 40 && wire == 2) {
      m.netDescription = r.readString();
    } else if (field == 41 && wire == 2) {
      m.netMacAddress = r.readString();
    } else if (field == 42 && wire == 2) {
      m.netDriverVersion = r.readString();
    } else if (field == 43 && wire == 2) {
      m.netDriverDate = r.readString();
    } else if (field == 44 && wire == 2) {
      m.netConnectionType = r.readString();
    } else if (field == 45 && wire == 2) {
      m.netDuplex = r.readString();
    } else if (field == 46 && wire == 0) {
      m.hasNetMtu = r.readVarint() != 0;
    } else if (field == 47 && wire == 0) {
      m.netMtu = r.readVarint();
    } else if (field == 48 && wire == 0) {
      m.hasNetIfIndex = r.readVarint() != 0;
    } else if (field == 49 && wire == 0) {
      m.netIfIndex = r.readVarint();
    } else if (field == 50 && wire == 0) {
      m.hasNetLinkSpeedBps = r.readVarint() != 0;
    } else if (field == 51 && wire == 0) {
      m.netLinkSpeedBps = r.readVarint();
    } else if (field == 52 && wire == 0) {
      m.hasNetDhcp = r.readVarint() != 0;
    } else if (field == 53 && wire == 0) {
      m.netDhcpEnabled = r.readVarint() != 0;
    } else if (field == 54 && wire == 2) {
      m.netDhcpServer = r.readString();
    } else if (field == 55 && wire == 0) {
      m.hasNetLeaseObtained = r.readVarint() != 0;
    } else if (field == 56 && wire == 0) {
      m.netLeaseObtainedUnixMs = r.readVarint();
    } else if (field == 57 && wire == 0) {
      m.hasNetLeaseExpires = r.readVarint() != 0;
    } else if (field == 58 && wire == 0) {
      m.netLeaseExpiresUnixMs = r.readVarint();
    } else if (field == 59 && wire == 0) {
      m.hasMemSlotsUsed = r.readVarint() != 0;
    } else if (field == 60 && wire == 0) {
      m.memSlotsUsed = r.readVarint();
    } else if (field == 61 && wire == 0) {
      m.hasMemModuleCount = r.readVarint() != 0;
    } else if (field == 62 && wire == 0) {
      m.memModuleCount = r.readVarint();
    } else if (field == 63 && wire == 2) {
      m.memDdrGeneration = r.readString();
    } else if (field == 64 && wire == 0) {
      m.hasMemSpeedMhz = r.readVarint() != 0;
    } else if (field == 65 && wire == 0) {
      m.memSpeedMhz = r.readVarint();
    } else if (field == 66 && wire == 2) {
      m.memFormFactor = r.readString();
    } else if (field == 67 && wire == 0) {
      m.hasMemEcc = r.readVarint() != 0;
    } else if (field == 68 && wire == 0) {
      m.memEcc = r.readVarint() != 0;
    } else if (field == 69 && wire == 0) {
      m.hasMemChannels = r.readVarint() != 0;
    } else if (field == 70 && wire == 0) {
      m.memChannels = r.readVarint();
    } else if (field == 71 && wire == 2) {
      m.memDimmVendor = r.readString();
    } else if (field == 72 && wire == 2) {
      m.memDimmPartNumber = r.readString();
    } else if (field == 73 && wire == 2) {
      m.memDimmSerial = r.readString();
    } else if (field == 74 && wire == 2) {
      m.diskInterface = r.readString();
    } else if (field == 75 && wire == 2) {
      m.diskBus = r.readString();
    } else if (field == 76 && wire == 2) {
      m.diskModel = r.readString();
    } else if (field == 77 && wire == 2) {
      m.diskSerial = r.readString();
    } else if (field == 78 && wire == 2) {
      m.diskFirmware = r.readString();
    } else if (field == 79 && wire == 2) {
      m.diskPartitionStyle = r.readString();
    } else if (field == 80 && wire == 0) {
      m.hasDiskSectorSize = r.readVarint() != 0;
    } else if (field == 81 && wire == 0) {
      m.diskSectorSize = r.readVarint();
    } else if (field == 82 && wire == 0) {
      m.hasDiskRotationRate = r.readVarint() != 0;
    } else if (field == 83 && wire == 0) {
      m.diskRotationRate = r.readVarint();
    } else if (field == 84 && wire == 0) {
      m.hasDiskTrim = r.readVarint() != 0;
    } else if (field == 85 && wire == 0) {
      m.diskTrimSupported = r.readVarint() != 0;
    } else if (field == 86 && wire == 2) {
      m.gpuPciLocation = r.readString();
    } else if (field == 87 && wire == 0) {
      m.hasGpuResizableBar = r.readVarint() != 0;
    } else if (field == 88 && wire == 0) {
      m.gpuResizableBar = r.readVarint() != 0;
    } else {
      r.skip(wire);
    }
  }
  return m;
}

HealthSample _decodeHealthSample(Uint8List data) {
  final r = _Reader(data);
  final m = HealthSample();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      m.unixMs = r.readVarint();
    } else if (field == 2 && wire == 0) {
      m.hasCpuPercent = r.readVarint() != 0;
    } else if (field == 3 && wire == 1) {
      m.cpuPercent = r.readDouble();
    } else if (field == 4 && wire == 0) {
      m.memoryUsedBytes = r.readVarint();
    } else if (field == 5 && wire == 0) {
      m.memoryTotalBytes = r.readVarint();
    } else if (field == 6 && wire == 0) {
      m.hasGpuPercent = r.readVarint() != 0;
    } else if (field == 7 && wire == 1) {
      m.gpuPercent = r.readDouble();
    } else if (field == 8 && wire == 0) {
      m.hasNetDownloadBps = r.readVarint() != 0;
    } else if (field == 9 && wire == 1) {
      m.netDownloadBps = r.readDouble();
    } else if (field == 10 && wire == 0) {
      m.hasNetUploadBps = r.readVarint() != 0;
    } else if (field == 11 && wire == 1) {
      m.netUploadBps = r.readDouble();
    } else if (field == 12 && wire == 0) {
      m.hasDiskReadBps = r.readVarint() != 0;
    } else if (field == 13 && wire == 1) {
      m.diskReadBps = r.readDouble();
    } else if (field == 14 && wire == 0) {
      m.hasDiskWriteBps = r.readVarint() != 0;
    } else if (field == 15 && wire == 1) {
      m.diskWriteBps = r.readDouble();
    } else if (field == 16 && wire == 0) {
      m.diskUsedBytes = r.readVarint();
    } else if (field == 17 && wire == 0) {
      m.diskTotalBytes = r.readVarint();
    } else if (field == 18 && wire == 0) {
      m.uptimeMs = r.readVarint();
    } else if (field == 19 && wire == 0) {
      m.hasCpuTempC = r.readVarint() != 0;
    } else if (field == 20 && wire == 1) {
      m.cpuTempC = r.readDouble();
    } else if (field == 21 && wire == 0) {
      m.hasGpuTempC = r.readVarint() != 0;
    } else if (field == 22 && wire == 1) {
      m.gpuTempC = r.readDouble();
    } else if (field == 23 && wire == 0) {
      m.hasSsdTempC = r.readVarint() != 0;
    } else if (field == 24 && wire == 1) {
      m.ssdTempC = r.readDouble();
    } else if (field == 25 && wire == 0) {
      m.hasCpuCurrentMhz = r.readVarint() != 0;
    } else if (field == 26 && wire == 1) {
      m.cpuCurrentMhz = r.readDouble();
    } else if (field == 27 && wire == 0) {
      m.memoryAvailableBytes = r.readVarint();
    } else if (field == 28 && wire == 0) {
      m.hasMemoryCommitted = r.readVarint() != 0;
    } else if (field == 29 && wire == 0) {
      m.memoryCommittedBytes = r.readVarint();
    } else if (field == 30 && wire == 0) {
      m.memoryCommitLimitBytes = r.readVarint();
    } else if (field == 31 && wire == 0) {
      m.hasMemoryCached = r.readVarint() != 0;
    } else if (field == 32 && wire == 0) {
      m.memoryCachedBytes = r.readVarint();
    } else if (field == 33 && wire == 2) {
      m.ipv4 = r.readString();
    } else if (field == 34 && wire == 2) {
      m.ipv6 = r.readString();
    } else if (field == 35 && wire == 2) {
      m.gateway = r.readString();
    } else if (field == 36 && wire == 2) {
      m.dns = r.readString();
    } else if (field == 37 && wire == 2) {
      m.topCpu.add(_decodeHealthProcessEntry(r.readBytes()));
    } else if (field == 38 && wire == 2) {
      m.topMemory.add(_decodeHealthProcessEntry(r.readBytes()));
    } else if (field == 39 && wire == 2) {
      m.topGpu.add(_decodeHealthProcessEntry(r.readBytes()));
    } else if (field == 40 && wire == 2) {
      m.topDisk.add(_decodeHealthProcessEntry(r.readBytes()));
    } else if (field == 41 && wire == 2) {
      m.topNetwork.add(_decodeHealthProcessEntry(r.readBytes()));
    } else if (field == 42 && wire == 1) {
      m.cpuCorePercent.add(r.readDouble());
    } else if (field == 43 && wire == 2) {
      m.volumes.add(_decodeHealthVolume(r.readBytes()));
    } else if (field == 44 && wire == 2) {
      m.disks.add(_decodeHealthPhysicalDisk(r.readBytes()));
    } else if (field == 45 && wire == 0) {
      m.hasMemoryCompressed = r.readVarint() != 0;
    } else if (field == 46 && wire == 0) {
      m.memoryCompressedBytes = r.readVarint();
    } else if (field == 47 && wire == 0) {
      m.hasMemoryHardwareReserved = r.readVarint() != 0;
    } else if (field == 48 && wire == 0) {
      m.memoryHardwareReservedBytes = r.readVarint();
    } else if (field == 49 && wire == 0) {
      m.hasMemoryPagedPool = r.readVarint() != 0;
    } else if (field == 50 && wire == 0) {
      m.memoryPagedPoolBytes = r.readVarint();
    } else if (field == 51 && wire == 0) {
      m.hasMemoryNonpagedPool = r.readVarint() != 0;
    } else if (field == 52 && wire == 0) {
      m.memoryNonpagedPoolBytes = r.readVarint();
    } else if (field == 53 && wire == 0) {
      m.hasMemoryPageFaultsPerSec = r.readVarint() != 0;
    } else if (field == 54 && wire == 1) {
      m.memoryPageFaultsPerSec = r.readDouble();
    } else if (field == 55 && wire == 0) {
      m.hasGpuUtil3d = r.readVarint() != 0;
    } else if (field == 56 && wire == 1) {
      m.gpuUtil3d = r.readDouble();
    } else if (field == 57 && wire == 0) {
      m.hasGpuUtilCompute = r.readVarint() != 0;
    } else if (field == 58 && wire == 1) {
      m.gpuUtilCompute = r.readDouble();
    } else if (field == 59 && wire == 0) {
      m.hasGpuUtilCopy = r.readVarint() != 0;
    } else if (field == 60 && wire == 1) {
      m.gpuUtilCopy = r.readDouble();
    } else if (field == 61 && wire == 0) {
      m.hasGpuUtilVideoDecode = r.readVarint() != 0;
    } else if (field == 62 && wire == 1) {
      m.gpuUtilVideoDecode = r.readDouble();
    } else if (field == 63 && wire == 0) {
      m.hasGpuUtilVideoEncode = r.readVarint() != 0;
    } else if (field == 64 && wire == 1) {
      m.gpuUtilVideoEncode = r.readDouble();
    } else if (field == 65 && wire == 0) {
      m.hasGpuDedicatedUsed = r.readVarint() != 0;
    } else if (field == 66 && wire == 0) {
      m.gpuDedicatedUsedBytes = r.readVarint();
    } else if (field == 67 && wire == 0) {
      m.hasGpuSharedUsed = r.readVarint() != 0;
    } else if (field == 68 && wire == 0) {
      m.gpuSharedUsedBytes = r.readVarint();
    } else if (field == 69 && wire == 0) {
      m.hasGpuClockMhz = r.readVarint() != 0;
    } else if (field == 70 && wire == 1) {
      m.gpuClockMhz = r.readDouble();
    } else if (field == 71 && wire == 0) {
      m.hasGpuMemoryClockMhz = r.readVarint() != 0;
    } else if (field == 72 && wire == 1) {
      m.gpuMemoryClockMhz = r.readDouble();
    } else if (field == 73 && wire == 0) {
      m.hasGpuFanRpm = r.readVarint() != 0;
    } else if (field == 74 && wire == 1) {
      m.gpuFanRpm = r.readDouble();
    } else if (field == 75 && wire == 0) {
      m.hasGpuPowerPercent = r.readVarint() != 0;
    } else if (field == 76 && wire == 1) {
      m.gpuPowerPercent = r.readDouble();
    } else if (field == 77 && wire == 0) {
      m.hasNetPeakDownloadBps = r.readVarint() != 0;
    } else if (field == 78 && wire == 1) {
      m.netPeakDownloadBps = r.readDouble();
    } else if (field == 79 && wire == 0) {
      m.hasNetPeakUploadBps = r.readVarint() != 0;
    } else if (field == 80 && wire == 1) {
      m.netPeakUploadBps = r.readDouble();
    } else if (field == 81 && wire == 0) {
      m.hasNetAvgDownloadBps = r.readVarint() != 0;
    } else if (field == 82 && wire == 1) {
      m.netAvgDownloadBps = r.readDouble();
    } else if (field == 83 && wire == 0) {
      m.hasNetAvgUploadBps = r.readVarint() != 0;
    } else if (field == 84 && wire == 1) {
      m.netAvgUploadBps = r.readDouble();
    } else if (field == 85 && wire == 0) {
      m.hasNetUtilizationPercent = r.readVarint() != 0;
    } else if (field == 86 && wire == 1) {
      m.netUtilizationPercent = r.readDouble();
    } else if (field == 87 && wire == 0) {
      m.hasNetConnectionMs = r.readVarint() != 0;
    } else if (field == 88 && wire == 0) {
      m.netConnectionMs = r.readVarint();
    } else if (field == 89 && wire == 0) {
      m.hasNetBytesSent = r.readVarint() != 0;
    } else if (field == 90 && wire == 0) {
      m.netBytesSent = r.readVarint();
    } else if (field == 91 && wire == 0) {
      m.hasNetBytesReceived = r.readVarint() != 0;
    } else if (field == 92 && wire == 0) {
      m.netBytesReceived = r.readVarint();
    } else if (field == 93 && wire == 0) {
      m.hasNetPacketsSent = r.readVarint() != 0;
    } else if (field == 94 && wire == 0) {
      m.netPacketsSent = r.readVarint();
    } else if (field == 95 && wire == 0) {
      m.hasNetPacketsReceived = r.readVarint() != 0;
    } else if (field == 96 && wire == 0) {
      m.netPacketsReceived = r.readVarint();
    } else if (field == 97 && wire == 0) {
      m.hasNetErrors = r.readVarint() != 0;
    } else if (field == 98 && wire == 0) {
      m.netErrors = r.readVarint();
    } else if (field == 99 && wire == 0) {
      m.hasNetDrops = r.readVarint() != 0;
    } else if (field == 100 && wire == 0) {
      m.netDrops = r.readVarint();
    } else if (field == 101 && wire == 2) {
      m.netSsid = r.readString();
    } else if (field == 102 && wire == 0) {
      m.hasNetSignalPercent = r.readVarint() != 0;
    } else if (field == 103 && wire == 1) {
      m.netSignalPercent = r.readDouble();
    } else if (field == 104 && wire == 2) {
      m.netWifiChannel = r.readString();
    } else if (field == 105 && wire == 2) {
      m.netWifiFrequency = r.readString();
    } else if (field == 106 && wire == 2) {
      m.netWifiSecurity = r.readString();
    } else if (field == 107 && wire == 0) {
      m.hasGpuUtilVideoProcessing = r.readVarint() != 0;
    } else if (field == 108 && wire == 1) {
      m.gpuUtilVideoProcessing = r.readDouble();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

GetHealthSnapshot _decodeGetHealthSnapshot(Uint8List data) {
  final r = _Reader(data);
  while (r.hasMore) {
    final tag = r.readVarint();
    final wire = tag & 7;
    r.skip(wire);
  }
  return GetHealthSnapshot();
}

HealthSnapshot _decodeHealthSnapshot(Uint8List data) {
  final r = _Reader(data);
  final m = HealthSnapshot();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      m.info = _decodeHealthStaticInfo(r.readBytes());
    } else if (field == 2 && wire == 2) {
      m.sample = _decodeHealthSample(r.readBytes());
    } else {
      r.skip(wire);
    }
  }
  return m;
}

HealthUpdate _decodeHealthUpdate(Uint8List data) {
  final r = _Reader(data);
  final m = HealthUpdate();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      m.sample = _decodeHealthSample(r.readBytes());
    } else if (field == 2 && wire == 2) {
      m.processInventory = _decodeHealthProcessInventoryUpdate(r.readBytes());
    } else {
      r.skip(wire);
    }
  }
  return m;
}

StartHealthMonitoring _decodeStartHealthMonitoring(Uint8List data) {
  final r = _Reader(data);
  while (r.hasMore) {
    final tag = r.readVarint();
    final wire = tag & 7;
    r.skip(wire);
  }
  return StartHealthMonitoring();
}

StopHealthMonitoring _decodeStopHealthMonitoring(Uint8List data) {
  final r = _Reader(data);
  while (r.hasMore) {
    final tag = r.readVarint();
    final wire = tag & 7;
    r.skip(wire);
  }
  return StopHealthMonitoring();
}

GetDiagnosticsSnapshot _decodeGetDiagnosticsSnapshot(Uint8List data) {
  final r = _Reader(data);
  while (r.hasMore) {
    final tag = r.readVarint();
    final wire = tag & 7;
    r.skip(wire);
  }
  return GetDiagnosticsSnapshot();
}

DiagnosticsSnapshot _decodeDiagnosticsSnapshot(Uint8List data) {
  final r = _Reader(data);
  final m = DiagnosticsSnapshot();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      m.serviceVersion = r.readString();
    } else if (field == 2 && wire == 0) {
      m.protocolVersion = r.readVarint();
    } else if (field == 3 && wire == 0) {
      m.serviceStartUnixMs = r.readVarint();
    } else if (field == 4 && wire == 0) {
      m.serviceUptimeMs = r.readVarint();
    } else if (field == 5 && wire == 2) {
      m.runMode = r.readString();
    } else if (field == 6 && wire == 0) {
      m.ipcListening = r.readVarint() != 0;
    } else if (field == 7 && wire == 0) {
      m.liveSubscribed = r.readVarint() != 0;
    } else if (field == 8 && wire == 2) {
      m.liveChannel = r.readString();
    } else if (field == 9 && wire == 0) {
      m.liveEventsPushed = r.readVarint();
    } else if (field == 10 && wire == 0) {
      m.liveEventsDropped = r.readVarint();
    } else if (field == 11 && wire == 0) {
      m.liveSubscriberReconnects = r.readVarint();
    } else if (field == 12 && wire == 0) {
      m.lastLiveEventUnixMs = r.readVarint();
    } else if (field == 13 && wire == 2) {
      m.lastLiveEventTitle = r.readString();
    } else if (field == 14 && wire == 0) {
      m.liveQueueDepth = r.readVarint();
    } else if (field == 15 && wire == 0) {
      m.liveQueueCapacity = r.readVarint();
    } else if (field == 16 && wire == 0) {
      m.ipcMessagesReceived = r.readVarint();
    } else if (field == 17 && wire == 0) {
      m.ipcMessagesSent = r.readVarint();
    } else if (field == 18 && wire == 0) {
      m.ipcErrors = r.readVarint();
    } else if (field == 19 && wire == 0) {
      m.connectedClients = r.readVarint();
    } else if (field == 20 && wire == 0) {
      m.servicePid = r.readVarint();
    } else if (field == 21 && wire == 0) {
      m.hasCpuPercent = r.readVarint() != 0;
    } else if (field == 22 && wire == 1) {
      m.cpuPercent = r.readDouble();
    } else if (field == 23 && wire == 0) {
      m.workingSetBytes = r.readVarint();
    } else if (field == 24 && wire == 0) {
      m.threadCount = r.readVarint();
    } else if (field == 25 && wire == 0) {
      m.handleCount = r.readVarint();
    } else if (field == 26 && wire == 0) {
      m.stageEventLog = r.readVarint();
    } else if (field == 27 && wire == 0) {
      m.stageCollector = r.readVarint();
    } else if (field == 28 && wire == 0) {
      m.stageIntelligence = r.readVarint();
    } else if (field == 29 && wire == 0) {
      m.stageIpc = r.readVarint();
    } else if (field == 30 && wire == 2) {
      m.stageDetail = r.readString();
    } else if (field == 31 && wire == 2) {
      m.windowsEdition = r.readString();
    } else if (field == 32 && wire == 2) {
      m.windowsVersion = r.readString();
    } else {
      r.skip(wire);
    }
  }
  return m;
}

InjectDiagnosticsTestEvent _decodeInjectDiagnosticsTestEvent(Uint8List data) {
  final r = _Reader(data);
  while (r.hasMore) {
    final tag = r.readVarint();
    final wire = tag & 7;
    r.skip(wire);
  }
  return InjectDiagnosticsTestEvent();
}

Envelope decodeEnvelope(Uint8List data) {
  final r = _Reader(data);
  final env = Envelope();
  while (r.hasMore) {
    final tag = r.readVarint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 0) {
      env.requestId = r.readVarint();
    } else if (wire == 2 &&
        (field == 10 ||
            field == 11 ||
            field == 12 ||
            field == 13 ||
            field == 14 ||
            field == 20 ||
            field == 21 ||
            field == 22 ||
            field == 23 ||
            field == 24 ||
            field == 25 ||
            field == 26 ||
            field == 27 ||
            field == 28 ||
            field == 29 ||
            field == 30 ||
            field == 31 ||
            field == 32 ||
            field == 33 ||
            field == 34 ||
            field == 99)) {
      final len = r.readVarint();
      final sub = r.data.sublist(r.offset, r.offset + len);
      r.offset += len;
      switch (field) {
        case 10:
          env.body = _decodeClientHello(sub);
          break;
        case 11:
          env.body = _decodeServerHello(sub);
          break;
        case 12:
          env.body = _decodePing(sub);
          break;
        case 13:
          env.body = _decodePong(sub);
          break;
        case 14:
          env.body = _decodeHeartbeat(sub);
          break;
        case 20:
          env.body = _decodeGetTimelineSnapshot(sub);
          break;
        case 21:
          env.body = _decodeTimelineSnapshot(sub);
          break;
        case 22:
          env.body = _decodeTimelineEvent(sub);
          break;
        case 23:
          env.body = _decodeStartLiveMonitoring(sub);
          break;
        case 24:
          env.body = _decodeStopLiveMonitoring(sub);
          break;
        case 25:
          env.body = _decodeGetHealthSnapshot(sub);
          break;
        case 26:
          env.body = _decodeHealthSnapshot(sub);
          break;
        case 27:
          env.body = _decodeHealthUpdate(sub);
          break;
        case 28:
          env.body = _decodeStartHealthMonitoring(sub);
          break;
        case 29:
          env.body = _decodeStopHealthMonitoring(sub);
          break;
        case 30:
          env.body = _decodeGetDiagnosticsSnapshot(sub);
          break;
        case 31:
          env.body = _decodeDiagnosticsSnapshot(sub);
          break;
        case 32:
          env.body = _decodeInjectDiagnosticsTestEvent(sub);
          break;
        case 33:
          env.body = _decodeGetProcessDetails(sub);
          break;
        case 34:
          env.body = _decodeProcessDetails(sub);
          break;
        case 99:
          env.body = _decodeError(sub);
          break;
      }
    } else {
      r.skip(wire);
    }
  }
  return env;
}

Uint8List encodeFrame(Uint8List payload) {
  if (payload.length > 2 * 1024 * 1024) {
    throw StateError('payload exceeds 2 MB');
  }
  final out = Uint8List(8 + payload.length);
  out[0] = 0x50;
  out[1] = 0x55;
  out[2] = 0x4C;
  out[3] = 0x53;
  final len = payload.length;
  out[4] = len & 0xff;
  out[5] = (len >> 8) & 0xff;
  out[6] = (len >> 16) & 0xff;
  out[7] = (len >> 24) & 0xff;
  out.setRange(8, out.length, payload);
  return out;
}

class FrameDecodeResult {
  FrameDecodeResult({required this.payload, required this.consumed});
  final Uint8List payload;
  final int consumed;
}

FrameDecodeResult? tryDecodeFrame(Uint8List data) {
  if (data.length < 8) return null;
  if (data[0] != 0x50 || data[1] != 0x55 || data[2] != 0x4C || data[3] != 0x53) {
    throw FormatException('invalid frame magic');
  }
  final plen = data[4] | (data[5] << 8) | (data[6] << 16) | (data[7] << 24);
  if (plen > 2 * 1024 * 1024) {
    throw FormatException('frame exceeds 2 MB');
  }
  if (data.length < 8 + plen) return null;
  return FrameDecodeResult(
    payload: data.sublist(8, 8 + plen),
    consumed: 8 + plen,
  );
}
