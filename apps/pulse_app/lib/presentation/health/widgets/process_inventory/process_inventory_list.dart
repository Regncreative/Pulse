import 'package:flutter/material.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../../app/theme/pulse_theme.dart';
import '../../health_view_models.dart';
import '../process_app_icon.dart';
import 'app_group_engine.dart';
import 'process_inventory_store.dart';

/// Which metric columns the process list shows.
enum ProcessListMetrics { standard, memory, gpu, network }

/// Column geometry shared by header + rows (keeps metrics aligned).
class _ProcessColumns {
  static const double padX = 10;
  static const double iconGap = 8;
  static const double icon = 16;
  static const double chevron = 18;
  static const double cpu = 56;
  static const double memory = 72;
  static const double disk = 72;
  static const double network = 76;
  static const double netDown = 72;
  static const double netUp = 72;
  static const double netTotal = 72;
  static const double gpu = 56;
  static const double gpuDed = 72;
  static const double gpuShared = 72;
  static const double metricGap = 4;
  static const double childIndent = 22;
}

/// Virtualized, categorized process list with Task Manager–style app groups.
class ProcessInventoryList extends StatefulWidget {
  const ProcessInventoryList({
    super.key,
    required this.store,
    this.compact = false,
    this.groupSort = ProcessGroupSort.nameAscending,
    this.memoryFormat = false,
    this.metrics = ProcessListMetrics.standard,
  });

  final ProcessInventoryStore store;
  final bool compact;
  final ProcessGroupSort groupSort;

  /// When true, Memory column uses [formatMemorySize] (X.XX GB / MB).
  final bool memoryFormat;

  /// Column set — [ProcessListMetrics.gpu] shows Name | GPU% | Ded. | Shared.
  final ProcessListMetrics metrics;

  @override
  State<ProcessInventoryList> createState() => _ProcessInventoryListState();
}

class _ProcessInventoryListState extends State<ProcessInventoryList> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final groups = AppGroupEngine.build(widget.store);
        final items = <_RowItem>[];

        void addSection(String title, ProcessCategory category) {
          final section = AppGroupEngine.inCategory(
            groups,
            category,
            sort: widget.groupSort,
          );
          if (section.isEmpty) return;
          items.add(_RowItem.header('$title (${section.length})'));
          for (final g in section) {
            items.add(_RowItem.group(g));
            if (_expanded.contains(g.id)) {
              for (final pid in g.memberPids) {
                items.add(_RowItem.child(pid));
              }
            }
          }
        }

        addSection('Apps', ProcessCategory.application);
        addSection('Background processes', ProcessCategory.background);
        addSection('Windows processes', ProcessCategory.windows);

        if (items.isEmpty) {
          return Center(
            child: Text(
              'Waiting for process inventory…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textTertiary,
                  ),
            ),
          );
        }

        final rowH = widget.compact ? 36.0 : 40.0;
        final headerH = widget.compact ? 26.0 : 28.0;
        final metrics = widget.metrics;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ColumnHeader(metrics: metrics),
            const Divider(height: 1, color: PulseTokens.strokeSubtle),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemExtentBuilder: (index, _) =>
                    items[index].isHeader ? headerH : rowH,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item.isHeader) {
                    return _SectionHeader(title: item.headerTitle!);
                  }
                  if (item.isGroup) {
                    final g = item.group!;
                    return _AppGroupRow(
                      group: g,
                      expanded: _expanded.contains(g.id),
                      selected: !_expanded.contains(g.id) &&
                          widget.store.selectedPid != null &&
                          g.memberPids.contains(widget.store.selectedPid),
                      memoryFormat: widget.memoryFormat,
                      metrics: metrics,
                      onToggleExpand: () {
                        setState(() {
                          if (_expanded.contains(g.id)) {
                            _expanded.remove(g.id);
                          } else {
                            _expanded.add(g.id);
                          }
                        });
                      },
                      onSelect: () {
                        widget.store.select(g.representativePid);
                        if (g.memberCount > 1 && !_expanded.contains(g.id)) {
                          setState(() => _expanded.add(g.id));
                        }
                      },
                    );
                  }
                  final entry = widget.store.entry(item.pid!);
                  if (entry == null) return const SizedBox.shrink();
                  return _ProcessChildRow(
                    entry: entry,
                    selected: widget.store.selectedPid == entry.pid,
                    memoryFormat: widget.memoryFormat,
                    metrics: metrics,
                    onTap: () => widget.store.select(entry.pid),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RowItem {
  _RowItem.header(this.headerTitle)
      : group = null,
        pid = null,
        isHeader = true,
        isGroup = false;
  _RowItem.group(this.group)
      : headerTitle = null,
        pid = null,
        isHeader = false,
        isGroup = true;
  _RowItem.child(this.pid)
      : headerTitle = null,
        group = null,
        isHeader = false,
        isGroup = false;

  final bool isHeader;
  final bool isGroup;
  final String? headerTitle;
  final ProcessAppGroup? group;
  final int? pid;
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.metrics});
  final ProcessListMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: PulseTokens.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _ProcessColumns.padX,
        vertical: 6,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: _ProcessColumns.chevron +
                _ProcessColumns.icon +
                _ProcessColumns.iconGap,
          ),
          Expanded(child: Text('Name', style: style)),
          if (metrics == ProcessListMetrics.gpu) ...[
            _metricHeader('GPU', _ProcessColumns.gpu, style),
            _metricHeader('Ded.', _ProcessColumns.gpuDed, style),
            _metricHeader('Shared', _ProcessColumns.gpuShared, style),
          ] else if (metrics == ProcessListMetrics.network) ...[
            _metricHeader('Down', _ProcessColumns.netDown, style),
            _metricHeader('Up', _ProcessColumns.netUp, style),
            _metricHeader('Total', _ProcessColumns.netTotal, style),
          ] else ...[
            _metricHeader('CPU', _ProcessColumns.cpu, style),
            _metricHeader('Memory', _ProcessColumns.memory, style),
            if (metrics == ProcessListMetrics.standard) ...[
              _metricHeader('Disk', _ProcessColumns.disk, style),
              _metricHeader('Network', _ProcessColumns.network, style),
            ],
          ],
        ],
      ),
    );
  }

  Widget _metricHeader(String label, double width, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.only(left: _ProcessColumns.metricGap),
      child: SizedBox(
        width: width,
        child: Text(label, textAlign: TextAlign.right, style: style),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: _ProcessColumns.padX),
      color: PulseTokens.sidebarSolid.withValues(alpha: 0.55),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: PulseTokens.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
      ),
    );
  }
}

class _AppGroupRow extends StatelessWidget {
  const _AppGroupRow({
    required this.group,
    required this.expanded,
    required this.selected,
    required this.onToggleExpand,
    required this.onSelect,
    this.memoryFormat = false,
    this.metrics = ProcessListMetrics.standard,
  });

  final ProcessAppGroup group;
  final bool expanded;
  final bool selected;
  final VoidCallback onToggleExpand;
  final VoidCallback onSelect;
  final bool memoryFormat;
  final ProcessListMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final metricStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: PulseTokens.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final title = '${group.displayName} (${group.memberCount})';

    return Material(
      color: selected
          ? PulseTokens.accent.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        onDoubleTap: onToggleExpand,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _ProcessColumns.padX),
          child: Row(
            children: [
              SizedBox(
                width: _ProcessColumns.chevron,
                child: group.memberCount > 1
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: _ProcessColumns.chevron,
                          minHeight: _ProcessColumns.chevron,
                        ),
                        iconSize: 16,
                        onPressed: onToggleExpand,
                        icon: Icon(
                          expanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          color: PulseTokens.textTertiary,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              ProcessAppIcon(
                path: group.iconPath,
                name: group.iconName,
                pid: group.representativePid,
                size: _ProcessColumns.icon,
              ),
              const SizedBox(width: _ProcessColumns.iconGap),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PulseTokens.textPrimary,
                      ),
                ),
              ),
              ..._metricCells(metricStyle),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _metricCells(TextStyle? metricStyle) {
    if (metrics == ProcessListMetrics.gpu) {
      final gpu = group.hasGpu
          ? formatCpuPercent(group.gpuPercent)
          : kUnavailableDash;
      final ded = group.gpuDedicatedBytes > 0
          ? formatMemorySize(group.gpuDedicatedBytes)
          : kUnavailableDash;
      final shared = group.gpuSharedBytes > 0
          ? formatMemorySize(group.gpuSharedBytes)
          : kUnavailableDash;
      return [
        _metricCell(gpu, _ProcessColumns.gpu, metricStyle),
        _metricCell(ded, _ProcessColumns.gpuDed, metricStyle),
        _metricCell(shared, _ProcessColumns.gpuShared, metricStyle),
      ];
    }

    if (metrics == ProcessListMetrics.network) {
      final down = group.hasNetDownload
          ? formatTransferRate(group.netDownloadBps)
          : kUnavailableDash;
      final up = group.hasNetUpload
          ? formatTransferRate(group.netUploadBps)
          : kUnavailableDash;
      final total = group.hasNet
          ? formatTransferRate(group.netBps)
          : kUnavailableDash;
      return [
        _metricCell(down, _ProcessColumns.netDown, metricStyle),
        _metricCell(up, _ProcessColumns.netUp, metricStyle),
        _metricCell(total, _ProcessColumns.netTotal, metricStyle),
      ];
    }

    final cpu = group.hasCpu
        ? formatCpuPercent(group.cpuPercent)
        : kUnavailableDash;
    final mem = group.hasMemory
        ? (memoryFormat
            ? formatMemorySize(group.memoryBytes)
            : formatBytesBinary(group.memoryBytes, fractionDigits: 0))
        : kUnavailableDash;
    if (metrics == ProcessListMetrics.memory) {
      return [
        _metricCell(cpu, _ProcessColumns.cpu, metricStyle),
        _metricCell(mem, _ProcessColumns.memory, metricStyle),
      ];
    }
    final disk = group.hasDisk
        ? formatTransferRate(group.diskBps)
        : kUnavailableDash;
    final net = group.hasNet
        ? formatTransferRate(group.netBps)
        : kUnavailableDash;
    return [
      _metricCell(cpu, _ProcessColumns.cpu, metricStyle),
      _metricCell(mem, _ProcessColumns.memory, metricStyle),
      _metricCell(disk, _ProcessColumns.disk, metricStyle),
      _metricCell(net, _ProcessColumns.network, metricStyle),
    ];
  }
}

class _ProcessChildRow extends StatelessWidget {
  const _ProcessChildRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    this.memoryFormat = false,
    this.metrics = ProcessListMetrics.standard,
  });

  final HealthProcessEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final bool memoryFormat;
  final ProcessListMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final imageName = entry.name.trim().isEmpty ? kUnavailableDash : entry.name;
    final metricStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: PulseTokens.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final title = '$imageName (PID ${entry.pid})';

    return Material(
      color: selected
          ? PulseTokens.accent.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(
            left: _ProcessColumns.padX + _ProcessColumns.childIndent,
            right: _ProcessColumns.padX,
          ),
          child: Row(
            children: [
              ProcessAppIcon(
                path: entry.path,
                name: imageName,
                pid: entry.pid,
                size: _ProcessColumns.icon,
              ),
              const SizedBox(width: _ProcessColumns.iconGap),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: PulseTokens.textPrimary,
                      ),
                ),
              ),
              ..._metricCells(metricStyle),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _metricCells(TextStyle? metricStyle) {
    if (metrics == ProcessListMetrics.gpu) {
      final gpu = entry.hasGpuPercent
          ? formatCpuPercent(entry.gpuPercent)
          : kUnavailableDash;
      final ded = entry.hasGpuDedicatedBytes
          ? formatMemorySize(entry.gpuDedicatedBytes)
          : kUnavailableDash;
      final shared = entry.hasGpuSharedBytes
          ? formatMemorySize(entry.gpuSharedBytes)
          : kUnavailableDash;
      return [
        _metricCell(gpu, _ProcessColumns.gpu, metricStyle),
        _metricCell(ded, _ProcessColumns.gpuDed, metricStyle),
        _metricCell(shared, _ProcessColumns.gpuShared, metricStyle),
      ];
    }

    if (metrics == ProcessListMetrics.network) {
      final down = entry.hasNetDownloadBps
          ? formatTransferRate(entry.netDownloadBps)
          : kUnavailableDash;
      final up = entry.hasNetUploadBps
          ? formatTransferRate(entry.netUploadBps)
          : kUnavailableDash;
      final total = entry.hasNetBps
          ? formatTransferRate(entry.netBps)
          : kUnavailableDash;
      return [
        _metricCell(down, _ProcessColumns.netDown, metricStyle),
        _metricCell(up, _ProcessColumns.netUp, metricStyle),
        _metricCell(total, _ProcessColumns.netTotal, metricStyle),
      ];
    }

    final cpu = entry.hasCpuPercent
        ? formatCpuPercent(entry.cpuPercent)
        : kUnavailableDash;
    final mem = entry.hasMemoryBytes
        ? (memoryFormat
            ? formatMemorySize(entry.memoryBytes)
            : formatBytesBinary(entry.memoryBytes, fractionDigits: 0))
        : kUnavailableDash;
    if (metrics == ProcessListMetrics.memory) {
      return [
        _metricCell(cpu, _ProcessColumns.cpu, metricStyle),
        _metricCell(mem, _ProcessColumns.memory, metricStyle),
      ];
    }
    final disk = entry.hasDiskBps
        ? formatTransferRate(entry.diskBps)
        : kUnavailableDash;
    final net = entry.hasNetBps
        ? formatTransferRate(entry.netBps)
        : kUnavailableDash;
    return [
      _metricCell(cpu, _ProcessColumns.cpu, metricStyle),
      _metricCell(mem, _ProcessColumns.memory, metricStyle),
      _metricCell(disk, _ProcessColumns.disk, metricStyle),
      _metricCell(net, _ProcessColumns.network, metricStyle),
    ];
  }
}

Widget _metricCell(String text, double width, TextStyle? style) {
  return Padding(
    padding: const EdgeInsets.only(left: _ProcessColumns.metricGap),
    child: SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    ),
  );
}
