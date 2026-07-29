import 'package:flutter/material.dart';

import '../../../app/theme/pulse_theme.dart';

/// Labeled content block used inside the Event Details panel.
class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
    this.expandChild = false,
  });

  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PulseTokens.textTertiary,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w600,
                ),
          ),
          SizedBox(height: expandChild ? 8 : 12),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}
