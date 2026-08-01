import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';
import '../components/pulse_loading.dart';

/// Shimmer / placeholder box for loading states.
///
/// Thin wrapper over [PulseLoadingBlock] that reads radii from the active theme.
class PulseSkeleton extends StatelessWidget {
  const PulseSkeleton({
    super.key,
    this.height = 64,
    this.width,
    this.borderRadius,
  });

  final double height;
  final double? width;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = context.pulseTheme;
    return PulseLoadingBlock(
      height: height,
      width: width,
      borderRadius:
          borderRadius ?? BorderRadius.circular(theme.radiusCard),
    );
  }
}

/// Multi-row skeleton list for page-level loading placeholders.
class PulseSkeletonList extends StatelessWidget {
  const PulseSkeletonList({
    super.key,
    this.rows = 5,
    this.rowHeight = 72,
    this.spacing = 12,
  });

  final int rows;
  final double rowHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final theme = context.pulseTheme;
    return Column(
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          PulseSkeleton(
            height: rowHeight,
            borderRadius: BorderRadius.circular(theme.radiusCard),
          ),
        ],
      ],
    );
  }
}
