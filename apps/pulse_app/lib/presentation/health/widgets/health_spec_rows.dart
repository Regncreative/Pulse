import 'package:flutter/material.dart';

import '../../../app/theme/pulse_theme.dart';
import '../health_view_models.dart';

/// A single label/value spec row, optionally with a small description line
/// (e.g. a usage percentage under a capacity value).
class HealthSpecRow {
  const HealthSpecRow({
    required this.label,
    required this.value,
    this.description,
  });

  final String label;
  final String value;
  final String? description;
}

/// A titled group of [HealthSpecRow]s used across the System Health detail
/// panels (GPU / Network / CPU / Memory / Disk overviews).
///
/// Renders nothing when [rows] is empty, so callers can build sections
/// conditionally (e.g. skip "Wireless" entirely on wired adapters).
class HealthSpecSection extends StatelessWidget {
  const HealthSpecSection({
    super.key,
    this.title,
    required this.rows,
    this.compact = false,
  });

  final String? title;
  final List<HealthSpecRow> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hasTitle = title != null && title!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTitle) ...[
          Text(
            title!.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: PulseTokens.textTertiary,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 10 : null,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
        ],
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 6 : 10),
          _HealthSpecRowTile(row: rows[i], compact: compact),
        ],
      ],
    );
  }
}

class _HealthSpecRowTile extends StatelessWidget {
  const _HealthSpecRowTile({required this.row, required this.compact});

  final HealthSpecRow row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlaceholder =
        row.value == kUnavailableDash || row.value == kNotSupported;
    final hasDescription = row.description?.trim().isNotEmpty ?? false;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            row.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: PulseTokens.textTertiary,
              fontSize: compact ? 11.5 : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                row.value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isPlaceholder
                      ? PulseTokens.textDisabled
                      : PulseTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 11.5 : null,
                ),
              ),
              if (hasDescription) ...[
                const SizedBox(height: 2),
                Text(
                  row.description!,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: PulseTokens.textTertiary,
                    fontSize: compact ? 10 : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
