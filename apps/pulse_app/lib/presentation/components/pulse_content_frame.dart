import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';

/// Centers page content and caps width on ultrawide displays.
class PulseContentFrame extends StatelessWidget {
  const PulseContentFrame({
    super.key,
    required this.child,
    this.maxWidth = PulseTokens.contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0, maxWidth).toDouble()
            : maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: child,
          ),
        );
      },
    );
  }
}
