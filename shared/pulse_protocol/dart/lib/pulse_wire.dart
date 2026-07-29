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
  })  : topCpu = topCpu ?? <HealthProcessEntry>[],
        topMemory = topMemory ?? <HealthProcessEntry>[],
        topGpu = topGpu ?? <HealthProcessEntry>[],
        topDisk = topDisk ?? <HealthProcessEntry>[],
        topNetwork = topNetwork ?? <HealthProcessEntry>[],
        cpuCorePercent = cpuCorePercent ?? <double>[];
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
  HealthUpdate({HealthSample? sample}) : sample = sample ?? HealthSample();
  HealthSample sample;
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
