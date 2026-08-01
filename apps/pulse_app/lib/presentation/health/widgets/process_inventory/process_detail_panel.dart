import 'package:flutter/material.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../../app/theme/pulse_theme.dart';
import '../../health_view_models.dart';
import '../process_app_icon.dart';
import 'process_display_name.dart';

const String kNotAvailable = 'Not available';

/// Detail sheet for a selected process (lazy enrichment from service).
class ProcessDetailPanel extends StatelessWidget {
  const ProcessDetailPanel({
    super.key,
    required this.entry,
    required this.details,
    required this.loading,
    required this.error,
    required this.onClose,
    this.compact = false,
  });

  final HealthProcessEntry entry;
  final ProcessDetails? details;
  final bool loading;
  final String? error;
  final VoidCallback onClose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final imageName = entry.name.trim().isEmpty ? kUnavailableDash : entry.name;
    final d = details;
    final product = (d?.hasProductName == true &&
            (d?.productName.isNotEmpty ?? false))
        ? d!.productName
        : null;
    final labels = ProcessDisplayNames.splitLabels(
      imageName: imageName,
      productName: product,
    );
    final primaryTitle = labels.primary;
    final secondaryTitle = labels.secondary;
    final path = _field(
      available: d?.hasPath == true && (d?.path.isNotEmpty ?? false),
      value: d?.path,
      fallback: entry.path.isNotEmpty ? entry.path : null,
    );
    final publisher = _field(
      available: d?.hasCompany == true && (d?.company.isNotEmpty ?? false),
      value: d?.company,
    );
    final cmdline = _field(
      available:
          d?.hasCommandLine == true && (d?.commandLine.isNotEmpty ?? false),
      value: d?.commandLine,
    );
    final createMs = d?.hasCreateTime == true
        ? d!.createTimeUnixMs
        : (entry.hasCreateTime ? entry.createTimeUnixMs : 0);
    final createLabel = createMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(createMs).toLocal().toString()
        : kNotAvailable;
    final threads = d?.threadCount ?? entry.threadCount;
    final handles = d?.handleCount ?? entry.handleCount;
    final parentPid = d?.hasParentPid == true ? '${d!.parentPid}' : kNotAvailable;
    final parentName = _field(
      available: d?.hasParentName == true && (d?.parentName.isNotEmpty ?? false),
      value: d?.parentName,
    );
    final user = _field(
      available: d?.hasUser == true && (d?.user.isNotEmpty ?? false),
      value: d?.user,
    );
    final integrity = _field(
      available: d?.hasIntegrityLevel == true &&
          (d?.integrityLevel.isNotEmpty ?? false),
      value: d?.integrityLevel,
    );
    final elevated = d?.hasElevated == true
        ? (d!.elevated ? 'Yes' : 'No')
        : kNotAvailable;
    final arch = _field(
      available:
          d?.hasArchitecture == true && (d?.architecture.isNotEmpty ?? false),
      value: d?.architecture,
    );

    return Container(
      decoration: BoxDecoration(
        color: PulseTokens.sidebarSolid.withValues(alpha: 0.96),
        border: Border(
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
                path: entry.path,
                name: imageName,
                pid: entry.pid,
                size: 20,
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (secondaryTitle != null)
                      Text(
                        secondaryTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: PulseTokens.textTertiary,
                            ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.error,
                  ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                _kv(context, 'PID', '${entry.pid}'),
                _kv(context, 'Parent PID', parentPid),
                _kv(context, 'Parent Process', parentName),
                _kv(
                  context,
                  'Threads',
                  threads > 0 ? '$threads' : kNotAvailable,
                ),
                _kv(
                  context,
                  'Handles',
                  handles > 0 ? '$handles' : kNotAvailable,
                ),
                _kv(context, 'Executable', imageName),
                _kv(context, 'Executable path', path),
                _kv(context, 'Publisher', publisher),
                _kv(context, 'User', user),
                _kv(context, 'Integrity Level', integrity),
                _kv(context, 'Elevated', elevated),
                _kv(context, 'Architecture', arch),
                _kv(context, 'Start time', createLabel),
                _kv(context, 'Command line', cmdline),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _field({
    required bool available,
    String? value,
    String? fallback,
  }) {
    if (available && value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (fallback != null && fallback.trim().isNotEmpty) {
      return fallback.trim();
    }
    return kNotAvailable;
  }

  Widget _kv(BuildContext context, String label, String value) {
    final missing = value == kNotAvailable || value == kUnavailableDash;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PulseTokens.textTertiary,
                ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: missing
                      ? PulseTokens.textDisabled
                      : PulseTokens.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
