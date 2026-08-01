import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';
import 'pulse_metric_row.dart';

/// Titled group of [PulseMetricRow]s. Renders nothing when [rows] is empty.
class PulseMetricSection extends StatelessWidget {
  const PulseMetricSection({
    super.key,
    this.title,
    required this.rows,
    this.compact = false,
  });

  final String? title;
  final List<PulseMetricRow> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = context.pulseTheme;
    final textTheme = Theme.of(context).textTheme;
    final hasTitle = title != null && title!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTitle) ...[
          Text(
            title!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: theme.textTertiary,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 10 : null,
            ),
          ),
          SizedBox(height: compact ? 6 : theme.spaceSm),
        ],
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 6 : 10),
          rows[i],
        ],
      ],
    );
  }
}
