import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../app/theme/pulse_theme.dart';
import '../../../features/timeline/widgets/detail_section.dart';
import '../health_cards.dart';
import '../health_view_models.dart';
import 'process_app_icon.dart';

/// Right-side System Health details panel for a selected metric group.
class HealthDetailsPanel extends StatelessWidget {
  const HealthDetailsPanel({
    super.key,
    required this.kind,
    required this.view,
    required this.onClose,
  });

  final HealthPanelKind kind;
  final HealthViewState view;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PulseTokens.sidebarSolid.withValues(alpha: 0.98),
        border: const Border(
          left: BorderSide(color: PulseTokens.strokeSubtle),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailsHeader(
            title: kind.title,
            subtitle: _subtitle(),
            onClose: onClose,
          ),
          const Divider(height: 1, color: PulseTokens.strokeSubtle),
          Expanded(
            child: _sectionsBody(),
          ),
        ],
      ),
    );
  }

  /// Single-viewport panel body — no scroll (mockup parity).
  Widget _sectionsBody() {
    return switch (kind) {
      HealthPanelKind.cpu => _CpuPanelBody(view: view),
      HealthPanelKind.memory => _MemoryPanelBody(view: view),
      HealthPanelKind.gpu => _GpuPanelBody(view: view),
      HealthPanelKind.disk => _DiskPanelBody(view: view),
      HealthPanelKind.network => _NetworkPanelBody(view: view),
    };
  }

  String? _subtitle() {
    final i = view.info;
    return switch (kind) {
      HealthPanelKind.cpu => _orNull(i?.cpuModel),
      HealthPanelKind.memory => (i?.installedRamBytes ?? 0) > 0
          ? formatBytesBinary(i!.installedRamBytes, fractionDigits: 0)
          : null,
      HealthPanelKind.gpu => _orNull(i?.gpuModel),
      HealthPanelKind.disk => (i?.primaryStorageBytes ?? 0) > 0
          ? formatBytesBinary(i!.primaryStorageBytes, fractionDigits: 0)
          : null,
      HealthPanelKind.network => _orNull(i?.activeNetworkAdapter),
    };
  }

  static String? _orNull(String? value) {
    final t = value?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

}

class _CpuPanelBody extends StatelessWidget {
  const _CpuPanelBody({required this.view});
  final HealthViewState view;

  @override
  Widget build(BuildContext context) {
    final s = view.sample;
    final i = view.info;
    final usagePct = s != null && s.hasCpuPercent ? s.cpuPercent : null;
    final currentMhz = s != null && s.hasCpuCurrentMhz
        ? formatMhz(s.cpuCurrentMhz)
        : kUnavailableDash;
    final baseMhz = (i?.cpuBaseMhz ?? 0) > 0
        ? formatMhz(i!.cpuBaseMhz)
        : kUnavailableDash;
    final cores = (i?.cpuCores ?? 0) > 0
        ? i!.cpuCores.toString()
        : kUnavailableDash;
    final threads = (i?.cpuLogicalProcessors ?? 0) > 0
        ? i!.cpuLogicalProcessors.toString()
        : kUnavailableDash;
    final virt = i == null
        ? kUnavailableDash
        : (i.cpuVirtualizationEnabled ? 'Enabled' : 'Disabled');

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _UsageGauge(
                  percent: usagePct,
                  label: usagePct != null
                      ? '${usagePct.toStringAsFixed(0)}% Usage'
                      : 'Usage',
                  compact: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SpecList(
                    compact: true,
                    rows: [
                      ('Speed', currentMhz),
                      ('Base Speed', baseMhz),
                      ('Cores', cores),
                      ('Logical Processors', threads),
                      ('Virtualization', virt),
                      (
                        'Temperature',
                        formatTempC(s?.hasCpuTempC ?? false, s?.cpuTempC ?? 0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 4,
          child: DetailSection(
            title: 'Top Processes',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: _ProcessList(
              processes: s?.topCpu ?? const [],
              kind: HealthPanelKind.cpu,
              compact: true,
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 3,
          child: DetailSection(
            title: view.coreHistories.isNotEmpty
                ? 'CPU History (Per Core)'
                : 'CPU History',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            expandChild: true,
            child: view.coreHistories.isNotEmpty
                ? _CoreHistoryGrid(
                    histories: view.coreHistories,
                    compact: true,
                  )
                : _HistorySparkline(
                    values: view.cpuHistory,
                    fillHeight: true,
                  ),
          ),
        ),
      ],
    );
  }
}

class _MemoryPanelBody extends StatelessWidget {
  const _MemoryPanelBody({required this.view});
  final HealthViewState view;

  @override
  Widget build(BuildContext context) {
    final s = view.sample;
    final used = s?.memoryUsedBytes ?? 0;
    final total = s?.memoryTotalBytes ?? 0;
    final usagePct = total > 0 ? used * 100.0 / total : null;
    final usedLabel = total > 0
        ? '${formatBytesBinary(used)} / ${formatBytesBinary(total, fractionDigits: 0)}'
        : kUnavailableDash;
    final available = (s?.memoryAvailableBytes ?? 0) > 0 || total > 0
        ? formatBytesBinary(s!.memoryAvailableBytes)
        : kUnavailableDash;
    final committed = s?.hasMemoryCommitted == true
        ? '${formatBytesBinary(s!.memoryCommittedBytes)} / ${formatBytesBinary(s.memoryCommitLimitBytes, fractionDigits: 0)}'
        : kUnavailableDash;
    final cached = s?.hasMemoryCached == true
        ? formatBytesBinary(s!.memoryCachedBytes)
        : kUnavailableDash;

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                _UsageGauge(
                  percent: usagePct,
                  label: usagePct != null
                      ? '${usagePct.toStringAsFixed(0)}% Usage'
                      : 'Usage',
                  compact: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SpecList(
                    compact: true,
                    rows: [
                      ('Used / Total', usedLabel),
                      ('Available', available),
                      ('Committed', committed),
                      ('Cached', cached),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 4,
          child: DetailSection(
            title: 'Top Processes',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: _ProcessList(
              processes: s?.topMemory ?? const [],
              kind: HealthPanelKind.memory,
              compact: true,
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 3,
          child: DetailSection(
            title: 'Memory History',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            expandChild: true,
            child: _HistorySparkline(
              values: view.memoryHistory,
              fillHeight: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _GpuPanelBody extends StatelessWidget {
  const _GpuPanelBody({required this.view});
  final HealthViewState view;

  @override
  Widget build(BuildContext context) {
    final s = view.sample;
    final i = view.info;
    final usagePct = s != null && s.hasGpuPercent ? s.gpuPercent : null;
    final dedicated = (i?.gpuDedicatedBytes ?? 0) > 0
        ? formatBytesBinary(i!.gpuDedicatedBytes, fractionDigits: 0)
        : kUnavailableDash;
    final shared = (i?.gpuSharedBytes ?? 0) > 0
        ? formatBytesBinary(i!.gpuSharedBytes, fractionDigits: 0)
        : kUnavailableDash;

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                _UsageGauge(
                  percent: usagePct,
                  label: usagePct != null
                      ? '${usagePct.toStringAsFixed(0)}% Usage'
                      : 'Usage',
                  compact: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SpecList(
                    compact: true,
                    rows: [
                      (
                        'Usage',
                        usagePct != null
                            ? '${usagePct.toStringAsFixed(1)} %'
                            : kUnavailableDash,
                      ),
                      ('Dedicated VRAM', dedicated),
                      ('Shared Memory', shared),
                      (
                        'Temperature',
                        formatTempC(s?.hasGpuTempC ?? false, s?.gpuTempC ?? 0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 4,
          child: DetailSection(
            title: 'Top Processes',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: _ProcessList(
              processes: s?.topGpu ?? const [],
              kind: HealthPanelKind.gpu,
              compact: true,
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 3,
          child: DetailSection(
            title: 'GPU History',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            expandChild: true,
            child: _HistorySparkline(
              values: view.gpuHistory,
              fillHeight: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _DiskPanelBody extends StatelessWidget {
  const _DiskPanelBody({required this.view});
  final HealthViewState view;

  @override
  Widget build(BuildContext context) {
    final s = view.sample;
    final i = view.info;
    final volumes = s?.volumes ?? const <HealthVolume>[];
    final disks = s?.disks ?? const <HealthPhysicalDisk>[];
    final total = s?.diskTotalBytes ?? i?.primaryStorageBytes ?? 0;
    final used = s?.diskUsedBytes ?? 0;
    final free = total > used ? total - used : 0;
    final usagePct = total > 0 ? used * 100.0 / total : null;
    final capacity = total > 0
        ? formatBytesBinary(total, fractionDigits: 0)
        : kUnavailableDash;
    final freeLabel =
        total > 0 ? formatBytesBinary(free) : kUnavailableDash;
    final read = s?.hasDiskReadBps == true
        ? formatDiskRate(s!.diskReadBps)
        : kNotSupported;
    final write = s?.hasDiskWriteBps == true
        ? formatDiskRate(s!.diskWriteBps)
        : kNotSupported;

    final volumeSpec = <(String, String)>[
      for (final v in volumes)
        if (v.hasCapacity && v.totalBytes > 0)
          (
            _diskPanelVolumeTitle(v),
            '${formatBytesBinary(v.usedBytes)} / ${formatBytesBinary(v.totalBytes, fractionDigits: 0)}',
          )
        else
          (_diskPanelVolumeTitle(v), _diskPanelVolumeUnavailable(v)),
    ];
    final diskSpec = <(String, String)>[
      for (final d in disks)
        (
          d.name.trim().isEmpty ? d.id : d.name,
          [
            if (d.hasReadBps) 'R ${formatDiskRate(d.readBps)}',
            if (d.hasWriteBps) 'W ${formatDiskRate(d.writeBps)}',
          ].join(' · ').ifEmpty(kUnavailableDash),
        ),
    ];

    return Column(
      children: [
        Expanded(
          flex: 4,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                _UsageGauge(
                  percent: usagePct,
                  label: usagePct != null
                      ? '${usagePct.toStringAsFixed(0)}% Used'
                      : 'Usage',
                  compact: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SpecList(
                    compact: true,
                    rows: [
                      ('Primary', capacity),
                      ('Free', freeLabel),
                      ('Read (total)', read),
                      ('Write (total)', write),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (volumeSpec.isNotEmpty) ...[
          const Divider(height: 1, color: PulseTokens.strokeSubtle),
          Expanded(
            flex: 3,
            child: DetailSection(
              title: 'Volumes',
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              expandChild: true,
              child: _SpecList(compact: true, rows: volumeSpec),
            ),
          ),
        ],
        if (diskSpec.isNotEmpty) ...[
          const Divider(height: 1, color: PulseTokens.strokeSubtle),
          Expanded(
            flex: 3,
            child: DetailSection(
              title: 'Physical disks',
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              expandChild: true,
              child: _SpecList(compact: true, rows: diskSpec),
            ),
          ),
        ],
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 4,
          child: DetailSection(
            title: 'Top Processes',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            expandChild: true,
            child: _ProcessList(
              processes: s?.topDisk ?? const [],
              kind: HealthPanelKind.disk,
              compact: true,
            ),
          ),
        ),
      ],
    );
  }
}

String _diskPanelVolumeTitle(HealthVolume v) {
  final id = v.id.trim().isEmpty ? v.mountPoint.trim() : v.id.trim();
  final label = v.label.trim();
  return label.isEmpty ? id : '$id · $label';
}

String _diskPanelVolumeUnavailable(HealthVolume v) {
  return switch (v.kind) {
    HealthDriveKind.remote => 'Network',
    HealthDriveKind.removable || HealthDriveKind.cdrom => 'No media',
    _ => kUnavailableDash,
  };
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

class _NetworkPanelBody extends StatelessWidget {
  const _NetworkPanelBody({required this.view});
  final HealthViewState view;

  @override
  Widget build(BuildContext context) {
    final s = view.sample;
    final adapter = view.info?.activeNetworkAdapter.trim() ?? '';
    String orDash(String v) => v.trim().isEmpty ? kUnavailableDash : v.trim();
    final download = s?.hasNetDownloadBps == true
        ? formatThroughputBps(s!.netDownloadBps)
        : kUnavailableDash;
    final upload = s?.hasNetUploadBps == true
        ? formatThroughputBps(s!.netUploadBps)
        : kUnavailableDash;

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: DetailSection(
            title: 'Overview',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            expandChild: true,
            child: Column(
              children: [
                _NetworkHeroValues(download: download, upload: upload),
                const SizedBox(height: 12),
                Expanded(
                  child: _SpecList(
                    compact: true,
                    rows: [
                      (
                        'Adapter',
                        adapter.isEmpty ? kUnavailableDash : adapter,
                      ),
                      ('IPv4', orDash(s?.ipv4 ?? '')),
                      ('IPv6', orDash(s?.ipv6 ?? '')),
                      ('Gateway', orDash(s?.gateway ?? '')),
                      ('DNS', orDash(s?.dns ?? '')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: PulseTokens.strokeSubtle),
        Expanded(
          flex: 5,
          child: DetailSection(
            title: 'Top Processes',
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            expandChild: true,
            child: _ProcessList(
              processes: s?.topNetwork ?? const [],
              kind: HealthPanelKind.network,
              compact: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({
    required this.title,
    required this.onClose,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PulseTokens.textTertiary,
                          height: 1.35,
                        ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(LucideIcons.x, size: 17),
          ),
        ],
      ),
    );
  }
}

class _UsageGauge extends StatelessWidget {
  const _UsageGauge({
    required this.percent,
    required this.label,
    this.compact = false,
  });

  final double? percent;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pct = percent?.clamp(0.0, 100.0);
    final size = compact ? 96.0 : 148.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _UsageDonutPainter(
              percent: pct ?? 0,
              hasValue: pct != null,
              accent: PulseTokens.accent,
              track: PulseTokens.strokeSubtle,
              strokeWidth: compact ? 8 : 11,
            ),
            child: Center(
              child: Text(
                pct != null ? '${pct.toStringAsFixed(0)}%' : kUnavailableDash,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: compact ? 20 : 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                      color: PulseTokens.textPrimary,
                    ),
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 6 : 12),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: PulseTokens.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: compact ? 11.5 : null,
              ),
        ),
      ],
    );
  }
}

class _UsageDonutPainter extends CustomPainter {
  _UsageDonutPainter({
    required this.percent,
    required this.hasValue,
    required this.accent,
    required this.track,
    this.strokeWidth = 11.0,
  });

  final double percent;
  final bool hasValue;
  final Color accent;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    if (!hasValue || percent <= 0) return;

    final sweep = (percent / 100.0).clamp(0.0, 1.0) * math.pi * 2;
    final fillPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Start at top (-pi/2).
    canvas.drawArc(rect, -math.pi / 2, sweep, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _UsageDonutPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.hasValue != hasValue ||
        oldDelegate.accent != accent ||
        oldDelegate.track != track ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _NetworkHeroValues extends StatelessWidget {
  const _NetworkHeroValues({
    required this.download,
    required this.upload,
  });

  final String download;
  final String upload;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ThroughputHero(
            label: 'Download',
            value: download,
            icon: LucideIcons.download,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ThroughputHero(
            label: 'Upload',
            value: upload,
            icon: LucideIcons.upload,
          ),
        ),
      ],
    );
  }
}

class _ThroughputHero extends StatelessWidget {
  const _ThroughputHero({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: PulseTokens.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        border: Border.all(color: PulseTokens.strokeSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: PulseTokens.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: PulseTokens.textTertiary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: PulseTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
          ),
        ],
      ),
    );
  }
}

class _SpecList extends StatelessWidget {
  const _SpecList({required this.rows, this.compact = false});

  final List<(String, String)> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment:
          compact ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 5 : 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  rows[i].$1,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PulseTokens.textTertiary,
                        fontSize: compact ? 11.5 : null,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  rows[i].$2,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: rows[i].$2 == kNotSupported ||
                                rows[i].$2 == kUnavailableDash
                            ? PulseTokens.textDisabled
                            : PulseTokens.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: compact ? 11.5 : null,
                      ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ProcessList extends StatelessWidget {
  const _ProcessList({
    required this.processes,
    required this.kind,
    this.compact = false,
  });

  final List<HealthProcessEntry> processes;
  final HealthPanelKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (processes.isEmpty) {
      return Text(
        kUnavailableDash,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: PulseTokens.textDisabled,
            ),
      );
    }

    final primaryLabel = processMetricColumnLabel(kind);
    final secondaryLabel = processSecondaryColumnLabel(kind);
    final shown = processes.take(5).toList();

    final rows = Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 4 : 8),
          if (compact)
            Expanded(
              child: _ProcessRow(
                entry: shown[i],
                kind: kind,
                compact: compact,
              ),
            )
          else
            _ProcessRow(entry: shown[i], kind: kind),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProcessColumnHeader(
          primaryLabel: primaryLabel,
          secondaryLabel: secondaryLabel,
        ),
        SizedBox(height: compact ? 4 : 8),
        if (compact) Expanded(child: rows) else rows,
      ],
    );
  }
}

class _ProcessColumnHeader extends StatelessWidget {
  const _ProcessColumnHeader({
    required this.primaryLabel,
    this.secondaryLabel,
  });

  final String primaryLabel;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: PulseTokens.textDisabled,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        );
    return Row(
      children: [
        Expanded(
          child: Text('Process', style: style),
        ),
        SizedBox(
          width: 72,
          child: Text(
            primaryLabel,
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
        if (secondaryLabel != null)
          SizedBox(
            width: 72,
            child: Text(
              secondaryLabel!,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
      ],
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    required this.entry,
    required this.kind,
    this.compact = false,
  });

  final HealthProcessEntry entry;
  final HealthPanelKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final name = entry.name.trim().isEmpty ? kUnavailableDash : entry.name;
    final metric = formatProcessPrimaryMetric(entry, kind);
    final secondary = formatProcessSecondaryMetric(entry, kind);
    final showSecondary = processSecondaryColumnLabel(kind) != null;
    final iconSize = compact ? 22.0 : 28.0;

    return Row(
      children: [
        ProcessAppIcon(
          path: entry.path,
          name: name,
          pid: entry.pid,
          size: iconSize,
        ),
        SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PulseTokens.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: compact ? 12 : null,
                ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: compact ? 56 : 72,
          child: Text(
            metric,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PulseTokens.textSecondary,
                  fontSize: compact ? 12 : null,
                ),
          ),
        ),
        if (showSecondary)
          SizedBox(
            width: compact ? 56 : 72,
            child: Text(
              secondary ?? kUnavailableDash,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: PulseTokens.textTertiary,
                    fontSize: compact ? 12 : null,
                  ),
            ),
          ),
      ],
    );
  }
}

class _CoreHistoryGrid extends StatelessWidget {
  const _CoreHistoryGrid({
    required this.histories,
    this.compact = false,
  });

  final List<List<double>> histories;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = histories.length;
        if (count == 0) {
          return const SizedBox.shrink();
        }

        final gap = compact ? 6.0 : 10.0;
        final minTileHeight = compact ? 36.0 : 52.0;
        final maxColumns = compact ? 6 : 4;

        // Grow columns until tiles fit the available height (any core count).
        var columns = count <= 4 ? 2 : 3;
        columns = columns.clamp(1, maxColumns);
        for (var c = columns; c <= maxColumns; c++) {
          final rows = (count / c).ceil();
          final tileH =
              (constraints.maxHeight - gap * (rows - 1).clamp(0, 99)) / rows;
          if (tileH >= minTileHeight || c == maxColumns) {
            columns = c;
            if (tileH >= minTileHeight) break;
          }
        }

        final rows = (count / columns).ceil().clamp(1, 999);
        final availableH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : minTileHeight * rows;
        final rawTileH =
            (availableH - gap * (rows - 1).clamp(0, 999)) / rows;
        final needsScroll = rawTileH < minTileHeight;
        final tileHeight = needsScroll
            ? minTileHeight
            : rawTileH.clamp(minTileHeight, availableH);
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        final grid = Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: _MiniCoreSparkline(
                  label: 'Core ${i + 1}',
                  values: histories[i],
                  compact: compact,
                ),
              ),
          ],
        );

        if (!needsScroll) return grid;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: grid,
        );
      },
    );
  }
}

class _MiniCoreSparkline extends StatelessWidget {
  const _MiniCoreSparkline({
    required this.label,
    required this.values,
    this.compact = false,
  });

  final String label;
  final List<double> values;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 4 : 8,
        compact ? 8 : 10,
        compact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: PulseTokens.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
        border: Border.all(color: PulseTokens.strokeSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PulseTokens.textTertiary,
                  fontSize: compact ? 10 : null,
                  height: 1.1,
                ),
          ),
          SizedBox(height: compact ? 2 : 6),
          Expanded(
            child: values.length < 2
                ? Center(
                    child: Text(
                      kUnavailableDash,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: PulseTokens.textDisabled,
                          ),
                    ),
                  )
                : CustomPaint(
                    painter: HealthSparklinePainter(
                      values: values,
                      color: PulseTokens.accent,
                    ),
                    child: const SizedBox.expand(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistorySparkline extends StatelessWidget {
  const _HistorySparkline({
    required this.values,
    this.fillHeight = false,
  });

  final List<double> values;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return Text(
        kUnavailableDash,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: PulseTokens.textDisabled,
            ),
      );
    }

    if (fillHeight) {
      return CustomPaint(
        painter: HealthSparklinePainter(
          values: values,
          color: PulseTokens.accent,
        ),
        child: const SizedBox.expand(),
      );
    }

    return SizedBox(
      height: 88,
      width: double.infinity,
      child: CustomPaint(
        painter: HealthSparklinePainter(
          values: values,
          color: PulseTokens.accent,
        ),
      ),
    );
  }
}

/// Animated host that expands the health details panel beside the list.
class HealthDetailsHost extends StatelessWidget {
  const HealthDetailsHost({
    super.key,
    required this.expanded,
    required this.width,
    required this.kind,
    required this.view,
    required this.onClose,
  });

  final bool expanded;
  final double width;
  final HealthPanelKind? kind;
  final HealthViewState view;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: PulseTokens.motionSlow,
        curve: PulseTokens.motionEmphasized,
        alignment: Alignment.centerRight,
        widthFactor: expanded ? 1 : 0,
        child: SizedBox(
          width: width,
          child: kind == null
              ? const SizedBox.shrink()
              : AnimatedSwitcher(
                  duration: PulseTokens.motionNormal,
                  switchInCurve: PulseTokens.motionCurve,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(kind),
                    child: HealthDetailsPanel(
                      kind: kind!,
                      view: view,
                      onClose: onClose,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
