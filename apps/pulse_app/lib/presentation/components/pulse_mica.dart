import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';

/// Soft Mica / Acrylic-inspired backdrop for the main content region.
class PulseMicaBackground extends StatelessWidget {
  const PulseMicaBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final depth = dark
        ? const Color(0xFF050508).withValues(alpha: 0.16)
        : const Color(0xFF1C1E24).withValues(alpha: 0.04);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: PulseTokens.canvas),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.85, -0.95),
              radius: 1.15,
              colors: [
                PulseTokens.canvasTint.withValues(alpha: dark ? 0.55 : 0.4),
                Colors.transparent,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.05, 1.1),
              radius: 1.0,
              colors: [
                PulseTokens.accent.withValues(alpha: dark ? 0.035 : 0.05),
                Colors.transparent,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                PulseTokens.micaOverlay,
                Colors.transparent,
                depth,
              ],
              stops: const [0, 0.35, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
