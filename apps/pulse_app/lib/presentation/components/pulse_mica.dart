import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';

/// Soft Mica / Acrylic-inspired backdrop for the main content region.
class PulseMicaBackground extends StatelessWidget {
  const PulseMicaBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: PulseTokens.canvas),
        // Subtle cool tint — reads like system Mica under dark chrome
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.85, -0.95),
              radius: 1.15,
              colors: [
                PulseTokens.canvasTint.withValues(alpha: 0.55),
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
                PulseTokens.accent.withValues(alpha: 0.035),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Soft top wash for depth without noise
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                PulseTokens.micaOverlay,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.12),
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
