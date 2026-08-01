import 'package:flutter/material.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../../app/theme/pulse_theme.dart';
import '../../health_view_models.dart';
import '../process_app_icon.dart';
import 'app_group_engine.dart';
import 'process_inventory_store.dart';

/// Memory-panel selection detail: application totals + per-child private WS.
class MemoryAppDetailPanel extends StatelessWidget {
  const MemoryAppDetailPanel({
    super.key,
    required this.group,
    required this.store,
    required this.onClose,
    this.compact = false,
  });

  final ProcessAppGroup group;
  final ProcessInventoryStore store;
  final VoidCallback onClose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final children = <HealthProcessEntry>[];
    for (final pid in group.memberPids) {
      final e = store.entry(pid);
      if (e != null) children.add(e);
    }

    final privateLabel = group.hasMemory
        ? formatMemorySize(group.privateWorkingSetSum)
        : kUnavailableDash;
    final commitLabel = group.commitBytesSum > 0
        ? formatMemorySize(group.commitBytesSum)
        : kUnavailableDash;
    final sharedLabel = group.workingSetBytesSum > 0
        ? formatMemorySize(group.sharedWorkingSetSum)
        : kUnavailableDash;
    final wsLabel = group.workingSetBytesSum > 0
        ? formatMemorySize(group.workingSetBytesSum)
        : kUnavailableDash;
    final pagedLabel = group.pagedPoolBytesSum > 0
        ? formatMemorySize(group.pagedPoolBytesSum)
        : kUnavailableDash;
    final nonpagedLabel = group.nonpagedPoolBytesSum > 0
        ? formatMemorySize(group.nonpagedPoolBytesSum)
        : kUnavailableDash;

    return Container(
      decoration: BoxDecoration(
        color: PulseTokens.sidebarSolid.withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: PulseTokens.strokeSubtle),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        compact ? 8 : 12,
        compact ? 6 : 10,
        compact ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProcessAppIcon(
                path: group.iconPath,
                name: group.iconName,
                pid: group.representativePid,
                size: 16,
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Text(
                  group.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              children: [
                _kv(context, 'Application', group.displayName),
                _kv(context, 'Total Private Working Set', privateLabel),
                _kv(context, 'Process count', '${group.memberCount}'),
                _kv(context, 'Commit', commitLabel),
                _kv(context, 'Shared Working Set', sharedLabel),
                _kv(context, 'Working Set', wsLabel),
                _kv(context, 'Private Working Set', privateLabel),
                _kv(context, 'Paged', pagedLabel),
                _kv(context, 'Non-paged', nonpagedLabel),
                if (children.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Processes',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: PulseTokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  for (final c in children)
                    _childRow(context, c),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _childRow(BuildContext context, HealthProcessEntry e) {
    final name = e.name.trim().isEmpty ? kUnavailableDash : e.name;
    final mem = e.hasMemoryBytes
        ? formatMemorySize(e.memoryBytes)
        : kUnavailableDash;
    final commit = e.hasCommitBytes
        ? formatMemorySize(e.commitBytes)
        : kUnavailableDash;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          ProcessAppIcon(
            path: e.path,
            name: name,
            pid: e.pid,
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$name (PID ${e.pid})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: PulseTokens.textPrimary,
                  ),
            ),
          ),
          Text(
            mem,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: PulseTokens.textSecondary,
                ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              commit,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: PulseTokens.textTertiary,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _kv(BuildContext context, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 168,
            child: Text(
              key,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textTertiary,
                    fontSize: 12,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textPrimary,
                    fontSize: 12,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
