import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pulse_protocol/pulse_wire.dart';

/// UI models for System Health — values come only from IPC samples.

enum HealthStatus { good, fair, elevated, unavailable }

/// Detail panel kinds for interactive System Health (TASK-007.2).
enum HealthPanelKind { cpu, memory, gpu, disk, network }

extension HealthPanelKindX on HealthPanelKind {
  String get title => switch (this) {
        HealthPanelKind.cpu => 'CPU',
        HealthPanelKind.memory => 'Memory',
        HealthPanelKind.gpu => 'GPU',
        HealthPanelKind.disk => 'Disk',
        HealthPanelKind.network => 'Network',
      };
}

/// Overall system posture for the top System Status card (TASK-007.1).
enum SystemStatusLevel { healthy, attention, critical }

class SystemStatusSummary {
  const SystemStatusSummary({
    required this.level,
    required this.title,
    required this.message,
  });

  final SystemStatusLevel level;
  final String title;
  final String message;
}

class HealthMetric {
  const HealthMetric({
    required this.id,
    required this.title,
    required this.value,
    required this.unit,
    required this.description,
    required this.status,
    required this.icon,
    this.sparkline = const [],
    this.available = true,
    this.attentionLabel,
    this.progress,
  });

  final String id;
  final String title;
  final String value;
  final String unit;
  final String description;
  final HealthStatus status;
  final IconData icon;
  final List<double> sparkline;
  final bool available;
  final String? attentionLabel;

  /// 0–1 fill for memory/storage progress bars; null = no bar.
  final double? progress;

  bool get needsAttention =>
      status == HealthStatus.fair || status == HealthStatus.elevated;
}

class HealthInfoItem {
  const HealthInfoItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class HealthDetailRow {
  const HealthDetailRow({
    required this.label,
    required this.value,
    this.available = true,
    this.progress,
  });

  final String label;
  final String value;
  final bool available;
  final double? progress;
}

const String kUnavailableDash = '—';
const String kNotSupported = 'Not supported';

String formatBytesBinary(int bytes, {int fractionDigits = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '${value.round()} ${units[unit]}';
  return '${value.toStringAsFixed(fractionDigits)} ${units[unit]}';
}

/// Task Manager–style memory sizes for the Memory panel.
///
/// - Below 1024 MB → `MB` (0–1 decimals)
/// - 1024 MB and above → `X.XX GB`
String formatMemorySize(int bytes) {
  if (bytes <= 0) return '0 MB';
  final mb = bytes / (1024.0 * 1024.0);
  if (mb < 1024.0) {
    if (mb >= 100) return '${mb.toStringAsFixed(0)} MB';
    if (mb >= 10) return '${mb.toStringAsFixed(1)} MB';
    return '${mb.toStringAsFixed(1)} MB';
  }
  final gb = mb / 1024.0;
  return '${gb.toStringAsFixed(2)} GB';
}

String formatThroughputBps(double bytesPerSec) {
  if (bytesPerSec < 0) bytesPerSec = 0;
  // Prefer Mbps for network hero; still accurate for disk.
  final bitsPerSec = bytesPerSec * 8.0;
  if (bitsPerSec >= 1e6) {
    return '${(bitsPerSec / 1e6).toStringAsFixed(1)} Mbps';
  }
  if (bitsPerSec >= 1e3) {
    return '${(bitsPerSec / 1e3).toStringAsFixed(0)} Kbps';
  }
  return '${bitsPerSec.toStringAsFixed(0)} bps';
}

String formatCpuPercent(double pct) {
  if (pct < 0) pct = 0;
  return '${pct.toStringAsFixed(1)}%';
}

String formatDiskRate(double bytesPerSec) {
  return formatTransferRate(bytesPerSec);
}

/// Transfer rate for Disk / Network columns (never raw byte counters).
String formatTransferRate(double bytesPerSec) {
  if (bytesPerSec < 0) bytesPerSec = 0;
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s', 'TB/s'];
  var value = bytesPerSec;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '${value.round()} ${units[unit]}';
  if (value >= 100) return '${value.round()} ${units[unit]}';
  if (value >= 10) {
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

String formatUptime(int uptimeMs) {
  if (uptimeMs <= 0) return kUnavailableDash;
  var seconds = uptimeMs ~/ 1000;
  final days = seconds ~/ 86400;
  seconds %= 86400;
  final hours = seconds ~/ 3600;
  seconds %= 3600;
  final minutes = seconds ~/ 60;
  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

String formatTempC(bool has, double value) {
  if (!has) return kNotSupported;
  return '${value.toStringAsFixed(0)} °C';
}

String formatMhz(num mhz) {
  if (mhz <= 0) return kUnavailableDash;
  return '${mhz.toStringAsFixed(0)} MHz';
}

/// Plain string field — dash when empty/whitespace-only.
String orDash(String? value) {
  final t = value?.trim() ?? '';
  return t.isEmpty ? kUnavailableDash : t;
}

/// Thousands-grouped integer counter, dash when unavailable.
String formatCount(bool has, int value) {
  if (!has) return kUnavailableDash;
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Size counter (e.g. GPU VRAM used) — dash when the driver never reported it.
String formatBytesOrDash(bool has, int bytes, {int fractionDigits = 1}) {
  if (!has) return kUnavailableDash;
  return formatBytesBinary(bytes, fractionDigits: fractionDigits);
}

/// Percentage counter that is usually always computable (net/CPU/mem) —
/// dash when unavailable rather than "not supported".
String formatPercentOrDash(bool has, double value, {int decimals = 1}) {
  if (!has) return kUnavailableDash;
  return '${value.toStringAsFixed(decimals)} %';
}

/// Vendor-dependent sensor/engine telemetry (GPU per-engine util, clocks,
/// fan, power draw) — many drivers never expose these, so use the same
/// "Not supported" wording as temperature rather than a bare dash.
String formatPercentOrNotSupported(bool has, double value, {int decimals = 1}) {
  if (!has) return kNotSupported;
  return '${value.toStringAsFixed(decimals)} %';
}

String formatMhzOrNotSupported(bool has, double mhz) {
  if (!has) return kNotSupported;
  return formatMhz(mhz);
}

String formatRpm(bool has, double rpm) {
  if (!has) return kNotSupported;
  return '${rpm.toStringAsFixed(0)} RPM';
}

/// Boolean configuration flag — "Not supported" when the capability was never
/// reported (e.g. Resizable BAR without a clean public query path).
String formatBoolOrNotSupported(bool has, bool value,
    {String yes = 'Yes', String no = 'No'}) {
  if (!has) return kNotSupported;
  return value ? yes : no;
}

/// Boolean configuration flag (Yes/No style) — dash when not queried.
String formatBoolOrDash(bool has, bool value, {String yes = 'Yes', String no = 'No'}) {
  if (!has) return kUnavailableDash;
  return value ? yes : no;
}

/// Boolean capability flag rendered as Supported/Not supported.
String formatSupportOrDash(bool has, bool value) {
  if (!has) return kUnavailableDash;
  return value ? 'Supported' : 'Not supported';
}

/// Network adapter link speed reported in bits/sec.
String formatLinkSpeedBps(bool has, int bps) {
  if (!has || bps <= 0) return kUnavailableDash;
  if (bps >= 1000000000) {
    final gbps = bps / 1000000000;
    return '${gbps.toStringAsFixed(gbps >= 10 ? 0 : 1)} Gbps';
  }
  if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(0)} Mbps';
  if (bps >= 1000) return '${(bps / 1000).toStringAsFixed(0)} Kbps';
  return '$bps bps';
}

/// Absolute date/time for DHCP lease timestamps.
String formatUnixMsDateTime(bool has, int ms) {
  if (!has || ms <= 0) return kUnavailableDash;
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${pad2(dt.month)}-${pad2(dt.day)} ${pad2(dt.hour)}:${pad2(dt.minute)}';
}

/// Elapsed connection duration (net adapter "connected for").
String formatConnectionDuration(bool has, int ms) {
  if (!has || ms <= 0) return kUnavailableDash;
  return formatUptime(ms);
}

/// Disk rotation rate — RPM value of 1 is the documented ATA IDENTIFY DEVICE
/// sentinel for "non-rotating media" (SSD), per ATA/ATAPI Command Set spec.
String formatRotationRate(bool has, int rpm) {
  if (!has || rpm <= 0) return kUnavailableDash;
  if (rpm == 1) return 'Solid state (no rotation)';
  return '$rpm RPM';
}

/// Primary metric shown next to a process name in the detail panel.
String formatProcessPrimaryMetric(
  HealthProcessEntry entry,
  HealthPanelKind kind,
) {
  switch (kind) {
    case HealthPanelKind.cpu:
      return entry.hasCpuPercent
          ? '${entry.cpuPercent.toStringAsFixed(1)} %'
          : kUnavailableDash;
    case HealthPanelKind.memory:
      return entry.hasMemoryBytes
          ? formatMemorySize(entry.memoryBytes)
          : kUnavailableDash;
    case HealthPanelKind.gpu:
      return entry.hasGpuPercent
          ? '${entry.gpuPercent.toStringAsFixed(1)} %'
          : kUnavailableDash;
    case HealthPanelKind.disk:
      return entry.hasDiskBps
          ? formatDiskRate(entry.diskBps)
          : kUnavailableDash;
    case HealthPanelKind.network:
      return entry.hasNetBps
          ? formatThroughputBps(entry.netBps)
          : kUnavailableDash;
  }
}

/// Optional secondary column in the detail process list (CPU shows memory).
String? formatProcessSecondaryMetric(
  HealthProcessEntry entry,
  HealthPanelKind kind,
) {
  switch (kind) {
    case HealthPanelKind.cpu:
      return entry.hasMemoryBytes
          ? formatBytesBinary(entry.memoryBytes)
          : null;
    case HealthPanelKind.memory:
      return entry.hasCpuPercent
          ? '${entry.cpuPercent.toStringAsFixed(1)} %'
          : null;
    case HealthPanelKind.gpu:
    case HealthPanelKind.disk:
    case HealthPanelKind.network:
      return null;
  }
}

String processMetricColumnLabel(HealthPanelKind kind) => switch (kind) {
      HealthPanelKind.cpu => 'CPU',
      HealthPanelKind.memory => 'Memory',
      HealthPanelKind.gpu => 'GPU',
      HealthPanelKind.disk => 'Disk',
      HealthPanelKind.network => 'Network',
    };

String? processSecondaryColumnLabel(HealthPanelKind kind) => switch (kind) {
      HealthPanelKind.cpu => 'Memory',
      HealthPanelKind.memory => 'CPU',
      HealthPanelKind.gpu ||
      HealthPanelKind.disk ||
      HealthPanelKind.network =>
        null,
    };

/// Last [max] samples from a rolling buffer (tiles show 60 of 300).
List<double> recentHistory(List<double> full, {int max = 60}) {
  if (full.length <= max) return List<double>.from(full);
  return full.sublist(full.length - max);
}

HealthStatus statusFromPercent(double percent) {
  if (percent >= 90) return HealthStatus.elevated;
  if (percent >= 75) return HealthStatus.fair;
  return HealthStatus.good;
}

SystemStatusSummary deriveSystemStatus(HealthSample? sample) {
  if (sample == null) {
    return const SystemStatusSummary(
      level: SystemStatusLevel.healthy,
      title: 'Healthy',
      message: 'Waiting for the first live sample.',
    );
  }

  final memPct = sample.memoryTotalBytes > 0
      ? sample.memoryUsedBytes * 100.0 / sample.memoryTotalBytes
      : 0.0;
  final diskPct = sample.diskTotalBytes > 0
      ? sample.diskUsedBytes * 100.0 / sample.diskTotalBytes
      : 0.0;
  final cpuPct = sample.hasCpuPercent ? sample.cpuPercent : 0.0;

  if (diskPct >= 95 || memPct >= 95 || cpuPct >= 95) {
    if (diskPct >= 95) {
      return const SystemStatusSummary(
        level: SystemStatusLevel.critical,
        title: 'Critical',
        message: 'Disk almost full.',
      );
    }
    if (memPct >= 95) {
      return const SystemStatusSummary(
        level: SystemStatusLevel.critical,
        title: 'Critical',
        message: 'Memory is nearly exhausted.',
      );
    }
    return const SystemStatusSummary(
      level: SystemStatusLevel.critical,
      title: 'Critical',
      message: 'CPU is under extreme load.',
    );
  }

  if (diskPct >= 85 || memPct >= 80 || cpuPct >= 85) {
    if (memPct >= 80) {
      return const SystemStatusSummary(
        level: SystemStatusLevel.attention,
        title: 'Attention',
        message: 'High memory usage detected.',
      );
    }
    if (diskPct >= 85) {
      return const SystemStatusSummary(
        level: SystemStatusLevel.attention,
        title: 'Attention',
        message: 'Disk space is running low.',
      );
    }
    return const SystemStatusSummary(
      level: SystemStatusLevel.attention,
      title: 'Attention',
      message: 'CPU usage is elevated.',
    );
  }

  return const SystemStatusSummary(
    level: SystemStatusLevel.healthy,
    title: 'Healthy',
    message: 'Everything looks normal.',
  );
}

/// Rolling history + latest static/live view models.
class HealthViewState {
  HealthViewState();

  /// ~5 minutes at 1 Hz; tiles use [recentHistory] of the last 60.
  static const int historyLimit = 300;

  HealthStaticInfo? info;
  HealthSample? sample;

  final List<double> cpuHistory = [];
  final List<double> memoryHistory = [];
  final List<double> gpuHistory = [];
  final List<double> diskHistory = [];
  final List<double> downloadHistory = [];
  final List<double> uploadHistory = [];

  /// Per-core CPU % series; length tracks [HealthSample.cpuCorePercent].
  final List<List<double>> coreHistories = [];

  /// Per-engine GPU utilization histories — only populated once the driver
  /// has reported the corresponding counter at least once.
  final List<double> gpu3dHistory = [];
  final List<double> gpuComputeHistory = [];
  final List<double> gpuCopyHistory = [];
  final List<double> gpuDecodeHistory = [];
  final List<double> gpuEncodeHistory = [];
  final List<double> gpuVideoProcessingHistory = [];

  /// VRAM usage histories in GB — same "only if ever reported" rule.
  final List<double> gpuDedicatedUsedHistory = [];
  final List<double> gpuSharedUsedHistory = [];

  void applySnapshot(HealthSnapshot snapshot) {
    info = snapshot.info;
    applySample(snapshot.sample);
  }

  void applySample(HealthSample next) {
    sample = next;
    _push(cpuHistory, next.hasCpuPercent ? next.cpuPercent : null);
    final memGb = next.memoryTotalBytes > 0
        ? next.memoryUsedBytes / (1024 * 1024 * 1024)
        : null;
    _push(memoryHistory, memGb);
    _push(gpuHistory, next.hasGpuPercent ? next.gpuPercent : null);
    // Disk activity as combined read+write MB/s for sparkline scale.
    if (next.hasDiskReadBps || next.hasDiskWriteBps) {
      final combined = (next.hasDiskReadBps ? next.diskReadBps : 0) +
          (next.hasDiskWriteBps ? next.diskWriteBps : 0);
      _push(diskHistory, combined / (1024 * 1024));
    } else {
      _push(diskHistory, null);
    }
    _push(
      downloadHistory,
      next.hasNetDownloadBps ? next.netDownloadBps : null,
    );
    _push(
      uploadHistory,
      next.hasNetUploadBps ? next.netUploadBps : null,
    );
    _syncCoreHistories(next.cpuCorePercent);

    if (next.hasGpuUtil3d) _push(gpu3dHistory, next.gpuUtil3d);
    if (next.hasGpuUtilCompute) _push(gpuComputeHistory, next.gpuUtilCompute);
    if (next.hasGpuUtilCopy) _push(gpuCopyHistory, next.gpuUtilCopy);
    if (next.hasGpuUtilVideoDecode) {
      _push(gpuDecodeHistory, next.gpuUtilVideoDecode);
    }
    if (next.hasGpuUtilVideoEncode) {
      _push(gpuEncodeHistory, next.gpuUtilVideoEncode);
    }
    if (next.hasGpuUtilVideoProcessing) {
      _push(gpuVideoProcessingHistory, next.gpuUtilVideoProcessing);
    }
    if (next.hasGpuDedicatedUsed) {
      _push(
        gpuDedicatedUsedHistory,
        next.gpuDedicatedUsedBytes / (1024 * 1024 * 1024),
      );
    }
    if (next.hasGpuSharedUsed) {
      _push(
        gpuSharedUsedHistory,
        next.gpuSharedUsedBytes / (1024 * 1024 * 1024),
      );
    }
  }

  void _push(List<double> series, double? value) {
    series.add(value ?? 0);
    while (series.length > historyLimit) {
      series.removeAt(0);
    }
  }

  void _syncCoreHistories(List<double> cores) {
    while (coreHistories.length < cores.length) {
      coreHistories.add(<double>[]);
    }
    while (coreHistories.length > cores.length) {
      coreHistories.removeLast();
    }
    for (var i = 0; i < cores.length; i++) {
      _push(coreHistories[i], cores[i]);
    }
  }

  SystemStatusSummary get systemStatus => deriveSystemStatus(sample);

  /// Deterministic score from system status + cpu/mem/disk load. No temps.
  int get healthScore {
    final summary = systemStatus;
    if (sample == null) return 95;

    final memPct = sample!.memoryTotalBytes > 0
        ? sample!.memoryUsedBytes * 100.0 / sample!.memoryTotalBytes
        : 0.0;
    final diskPct = sample!.diskTotalBytes > 0
        ? sample!.diskUsedBytes * 100.0 / sample!.diskTotalBytes
        : 0.0;
    final cpuPct = sample!.hasCpuPercent ? sample!.cpuPercent : 0.0;
    final peak = [cpuPct, memPct, diskPct]
        .reduce((a, b) => a > b ? a : b);

    return switch (summary.level) {
      SystemStatusLevel.critical => 40,
      SystemStatusLevel.attention => 70,
      SystemStatusLevel.healthy =>
        (98 - (peak * 0.08)).round().clamp(90, 98),
    };
  }

  String get lastUpdatedLabel {
    final ms = sample?.unixMs ?? 0;
    if (ms <= 0) return kUnavailableDash;
    final deltaMs = DateTime.now().millisecondsSinceEpoch - ms;
    if (deltaMs < 1500) return 'Just now';
    final sec = (deltaMs / 1000).round();
    if (sec < 60) return '$sec sec ago';
    final min = (sec / 60).round();
    if (min == 1) return '1 min ago';
    if (min < 60) return '$min min ago';
    return formatUptime(deltaMs);
  }

  List<HealthMetric> get heroMetrics {
    final s = sample;
    if (s == null) {
      return [
        _unavailableHero('cpu', 'CPU', LucideIcons.cpu),
        _unavailableHero('memory', 'Memory', LucideIcons.memoryStick),
        _unavailableHero('gpu', 'GPU', LucideIcons.circuitBoard),
        _unavailableHero('download', 'Download', LucideIcons.download),
        _unavailableHero('upload', 'Upload', LucideIcons.upload),
      ];
    }

    final memUsedGb = s.memoryUsedBytes / (1024 * 1024 * 1024);
    final memTotalGb = s.memoryTotalBytes / (1024 * 1024 * 1024);
    final memPct = s.memoryTotalBytes > 0
        ? (s.memoryUsedBytes * 100.0 / s.memoryTotalBytes)
        : 0.0;

    return [
      HealthMetric(
        id: 'cpu',
        title: 'CPU',
        value: s.hasCpuPercent ? s.cpuPercent.toStringAsFixed(0) : kUnavailableDash,
        unit: s.hasCpuPercent ? '%' : '',
        description: '',
        status: s.hasCpuPercent
            ? statusFromPercent(s.cpuPercent)
            : HealthStatus.unavailable,
        icon: LucideIcons.cpu,
        available: s.hasCpuPercent,
        sparkline: recentHistory(cpuHistory, max: 60),
      ),
      HealthMetric(
        id: 'memory',
        title: 'Memory',
        value: s.memoryTotalBytes > 0
            ? memUsedGb.toStringAsFixed(1)
            : kUnavailableDash,
        unit: s.memoryTotalBytes > 0 ? 'GB' : '',
        description: s.memoryTotalBytes > 0
            ? 'of ${memTotalGb.toStringAsFixed(0)} GB'
            : '',
        status: s.memoryTotalBytes > 0
            ? statusFromPercent(memPct)
            : HealthStatus.unavailable,
        icon: LucideIcons.memoryStick,
        available: s.memoryTotalBytes > 0,
        progress: s.memoryTotalBytes > 0 ? (memPct / 100.0).clamp(0.0, 1.0) : null,
      ),
      HealthMetric(
        id: 'gpu',
        title: 'GPU',
        value: s.hasGpuPercent
            ? s.gpuPercent.toStringAsFixed(0)
            : kUnavailableDash,
        unit: s.hasGpuPercent ? '%' : '',
        description: '',
        status: s.hasGpuPercent
            ? statusFromPercent(s.gpuPercent)
            : HealthStatus.unavailable,
        icon: LucideIcons.circuitBoard,
        available: s.hasGpuPercent,
        sparkline: recentHistory(gpuHistory, max: 60),
      ),
      HealthMetric(
        id: 'download',
        title: 'Download',
        value: s.hasNetDownloadBps
            ? formatThroughputBps(s.netDownloadBps)
            : kUnavailableDash,
        unit: '',
        description: '',
        status: HealthStatus.good,
        icon: LucideIcons.download,
        available: s.hasNetDownloadBps,
        sparkline: recentHistory(downloadHistory, max: 60),
      ),
      HealthMetric(
        id: 'upload',
        title: 'Upload',
        value: s.hasNetUploadBps
            ? formatThroughputBps(s.netUploadBps)
            : kUnavailableDash,
        unit: '',
        description: '',
        status: HealthStatus.good,
        icon: LucideIcons.upload,
        available: s.hasNetUploadBps,
        sparkline: recentHistory(uploadHistory, max: 60),
      ),
    ];
  }

  List<HealthInfoItem> get systemSummary {
    final i = info;
    final s = sample;
    String orDash(String v) => v.trim().isEmpty ? kUnavailableDash : v.trim();
    return [
      HealthInfoItem(
        label: 'Windows',
        value: i == null
            ? kUnavailableDash
            : orDash(
                [
                  if (i.windowsEdition.isNotEmpty) i.windowsEdition,
                  if (i.windowsVersion.isNotEmpty) i.windowsVersion,
                ].join(' '),
              ),
        icon: LucideIcons.monitor,
      ),
      HealthInfoItem(
        label: 'CPU',
        value: orDash(i?.cpuModel ?? ''),
        icon: LucideIcons.cpu,
      ),
      HealthInfoItem(
        label: 'GPU',
        value: orDash(i?.gpuModel ?? ''),
        icon: LucideIcons.circuitBoard,
      ),
      HealthInfoItem(
        label: 'Memory',
        value: (i?.installedRamBytes ?? 0) > 0
            ? formatBytesBinary(i!.installedRamBytes, fractionDigits: 0)
            : kUnavailableDash,
        icon: LucideIcons.memoryStick,
      ),
      HealthInfoItem(
        label: 'Uptime',
        value: formatUptime(s?.uptimeMs ?? 0),
        icon: LucideIcons.clock,
      ),
    ];
  }

  List<HealthMetric> get performanceMetrics {
    final s = sample;
    final cpuVal = s != null && s.hasCpuPercent
        ? s.cpuPercent.toStringAsFixed(0)
        : kUnavailableDash;
    final memVal = s != null && s.memoryTotalBytes > 0
        ? (s.memoryUsedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)
        : kUnavailableDash;
    final gpuVal = s != null && s.hasGpuPercent
        ? s.gpuPercent.toStringAsFixed(0)
        : kUnavailableDash;
    final diskMb = s == null
        ? null
        : ((s.hasDiskReadBps ? s.diskReadBps : 0) +
                (s.hasDiskWriteBps ? s.diskWriteBps : 0)) /
            (1024 * 1024);
    final diskVal = diskMb == null
        ? kUnavailableDash
        : diskMb.toStringAsFixed(diskMb >= 10 ? 0 : 1);

    return [
      HealthMetric(
        id: 'perf-cpu',
        title: 'CPU',
        value: cpuVal,
        unit: s != null && s.hasCpuPercent ? '%' : '',
        description: '',
        status: HealthStatus.good,
        icon: LucideIcons.cpu,
        sparkline: recentHistory(cpuHistory, max: 60),
        available: s?.hasCpuPercent ?? false,
      ),
      HealthMetric(
        id: 'perf-memory',
        title: 'Memory',
        value: memVal,
        unit: s != null && s.memoryTotalBytes > 0 ? 'GB' : '',
        description: '',
        status: HealthStatus.good,
        icon: LucideIcons.memoryStick,
        sparkline: recentHistory(memoryHistory, max: 60),
        available: (s?.memoryTotalBytes ?? 0) > 0,
      ),
      HealthMetric(
        id: 'perf-gpu',
        title: 'GPU',
        value: gpuVal,
        unit: s != null && s.hasGpuPercent ? '%' : '',
        description: '',
        status: HealthStatus.good,
        icon: LucideIcons.monitor,
        sparkline: recentHistory(gpuHistory, max: 60),
        available: s?.hasGpuPercent ?? false,
      ),
      HealthMetric(
        id: 'perf-disk',
        title: 'Disk',
        value: diskVal,
        unit: diskMb != null ? 'MB/s' : '',
        description: '',
        status: HealthStatus.good,
        icon: LucideIcons.hardDrive,
        sparkline: recentHistory(diskHistory, max: 60),
        available: diskMb != null,
      ),
    ];
  }

  List<HealthDetailRow> get hardwareRows {
    final s = sample;
    final rows = <HealthDetailRow>[
      HealthDetailRow(
        label: 'CPU Temperature',
        value: formatTempC(s?.hasCpuTempC ?? false, s?.cpuTempC ?? 0),
        available: s?.hasCpuTempC ?? false,
      ),
      HealthDetailRow(
        label: 'GPU Temperature',
        value: formatTempC(s?.hasGpuTempC ?? false, s?.gpuTempC ?? 0),
        available: s?.hasGpuTempC ?? false,
      ),
      HealthDetailRow(
        label: 'SSD Temperature',
        value: formatTempC(s?.hasSsdTempC ?? false, s?.ssdTempC ?? 0),
        available: s?.hasSsdTempC ?? false,
      ),
    ];
    // Keep unsupported sensors visible with "Not supported" (TASK-007.1).
    return rows;
  }

  double? get storageProgress {
    final s = sample;
    final total = s?.diskTotalBytes ?? info?.primaryStorageBytes ?? 0;
    final used = s?.diskUsedBytes ?? 0;
    if (total <= 0) return null;
    return (used / total).clamp(0.0, 1.0);
  }

  List<HealthDetailRow> get storageRows {
    final s = sample;
    final i = info;
    final volumes = s?.volumes ?? const <HealthVolume>[];
    final rows = <HealthDetailRow>[];

    if (volumes.isEmpty) {
      final total = s?.diskTotalBytes ?? i?.primaryStorageBytes ?? 0;
      final used = s?.diskUsedBytes ?? 0;
      final free = total > used ? total - used : 0;
      rows.add(
        HealthDetailRow(
          label: 'Disk Usage',
          value: total > 0
              ? '${formatBytesBinary(used)} of ${formatBytesBinary(total, fractionDigits: 0)}'
              : kUnavailableDash,
          available: total > 0,
          progress: storageProgress,
        ),
      );
      rows.add(
        HealthDetailRow(
          label: 'Available Space',
          value:
              total > 0 ? '${formatBytesBinary(free)} free' : kUnavailableDash,
          available: total > 0,
        ),
      );
    } else {
      for (final v in volumes) {
        final label = _volumeRowLabel(v);
        if (v.hasCapacity && v.totalBytes > 0) {
          rows.add(
            HealthDetailRow(
              label: label,
              value:
                  '${formatBytesBinary(v.usedBytes)} of ${formatBytesBinary(v.totalBytes, fractionDigits: 0)}',
              available: true,
              progress: (v.usedBytes / v.totalBytes).clamp(0.0, 1.0),
            ),
          );
        } else {
          rows.add(
            HealthDetailRow(
              label: label,
              value: _volumeUnavailableReason(v),
              available: false,
            ),
          );
        }
      }
    }

    rows.add(
      HealthDetailRow(
        label: 'Read Speed',
        value: s?.hasDiskReadBps == true
            ? formatDiskRate(s!.diskReadBps)
            : kNotSupported,
        available: s?.hasDiskReadBps ?? false,
      ),
    );
    rows.add(
      HealthDetailRow(
        label: 'Write Speed',
        value: s?.hasDiskWriteBps == true
            ? formatDiskRate(s!.diskWriteBps)
            : kNotSupported,
        available: s?.hasDiskWriteBps ?? false,
      ),
    );
    return rows;
  }

  List<HealthDetailRow> get networkRows {
    final s = sample;
    final adapter = info?.activeNetworkAdapter.trim() ?? '';
    return [
      HealthDetailRow(
        label: 'Download',
        value: s?.hasNetDownloadBps == true
            ? formatThroughputBps(s!.netDownloadBps)
            : kUnavailableDash,
        available: s?.hasNetDownloadBps ?? false,
      ),
      HealthDetailRow(
        label: 'Upload',
        value: s?.hasNetUploadBps == true
            ? formatThroughputBps(s!.netUploadBps)
            : kUnavailableDash,
        available: s?.hasNetUploadBps ?? false,
      ),
      HealthDetailRow(
        label: 'Adapter',
        value: adapter.isEmpty ? kUnavailableDash : adapter,
        available: adapter.isNotEmpty,
      ),
      HealthDetailRow(
        label: 'Connection Status',
        value: adapter.isEmpty ? kUnavailableDash : 'Connected',
        available: adapter.isNotEmpty,
      ),
    ];
  }
}

String _volumeRowLabel(HealthVolume v) {
  final id = v.id.trim().isEmpty ? v.mountPoint.trim() : v.id.trim();
  final label = v.label.trim();
  final kind = switch (v.kind) {
    HealthDriveKind.remote => 'Network',
    HealthDriveKind.removable => 'Removable',
    HealthDriveKind.cdrom => 'Optical',
    HealthDriveKind.ramdisk => 'RAM',
    _ => '',
  };
  final base = label.isEmpty ? id : '$id $label';
  if (kind.isEmpty) return base;
  return '$base ($kind)';
}

String _volumeUnavailableReason(HealthVolume v) {
  return switch (v.kind) {
    HealthDriveKind.remote => 'Network — capacity not queried',
    HealthDriveKind.removable => 'No media',
    HealthDriveKind.cdrom => 'No media',
    _ => kUnavailableDash,
  };
}

HealthMetric _unavailableHero(
  String id,
  String title,
  IconData icon,
) {
  return HealthMetric(
    id: id,
    title: title,
    value: kUnavailableDash,
    unit: '',
    description: '',
    status: HealthStatus.unavailable,
    icon: icon,
    available: false,
  );
}
