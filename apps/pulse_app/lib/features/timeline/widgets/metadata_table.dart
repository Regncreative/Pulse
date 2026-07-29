import 'package:flutter/material.dart';

import '../../../app/theme/pulse_theme.dart';

class MetadataEntry {
  const MetadataEntry(this.label, this.value);

  final String label;
  final String value;
}

/// Compact label/value table for technical and raw metadata.
class MetadataTable extends StatelessWidget {
  const MetadataTable({
    super.key,
    required this.entries,
    this.dense = false,
  });

  final List<MetadataEntry> entries;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final e in entries)
        if (e.value.trim().isNotEmpty) e,
    ];
    if (visible.isEmpty) {
      return Text(
        'No metadata available.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: PulseTokens.textTertiary,
            ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) SizedBox(height: dense ? 8 : 10),
          _MetadataRow(
            label: visible[i].label,
            value: visible[i].value,
            dense: dense,
          ),
        ],
      ],
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
    required this.dense,
  });

  final String label;
  final String value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: dense ? 108 : 120,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.textTertiary,
                  height: 1.35,
                ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.textPrimary,
                  height: 1.35,
                  fontFamily: 'Consolas',
                  fontSize: dense ? 12 : 12.5,
                ),
          ),
        ),
      ],
    );
  }
}
