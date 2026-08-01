import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';

/// A single label / value metric row with optional description under the value.
class PulseMetricRow extends StatelessWidget {
  const PulseMetricRow({
    super.key,
    required this.label,
    required this.value,
    this.description,
    this.compact = false,
    this.placeholder = false,
  });

  final String label;
  final String value;
  final String? description;
  final bool compact;

  /// When true, value uses the disabled text color (e.g. "—" placeholders).
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = context.pulseTheme;
    final textTheme = Theme.of(context).textTheme;
    final hasDescription = description?.trim().isNotEmpty ?? false;
    final tooltipMessage = placeholder
        ? null
        : [
            value,
            if (hasDescription) description!.trim(),
          ].join('\n');

    final valueColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: placeholder ? theme.textDisabled : theme.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: compact ? 11.5 : null,
          ),
        ),
        if (hasDescription) ...[
          const SizedBox(height: 2),
          Text(
            description!,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: theme.textTertiary,
              fontSize: compact ? 10 : null,
            ),
          ),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: theme.textTertiary,
              fontSize: compact ? 11.5 : null,
            ),
          ),
        ),
        SizedBox(width: theme.spaceSm + 4),
        Flexible(
          child: tooltipMessage == null
              ? valueColumn
              : Tooltip(
                  message: tooltipMessage,
                  waitDuration: const Duration(milliseconds: 450),
                  child: valueColumn,
                ),
        ),
      ],
    );
  }
}
