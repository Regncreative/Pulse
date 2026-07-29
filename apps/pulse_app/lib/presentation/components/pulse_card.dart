import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';
import 'safe_hover.dart';

class PulseCard extends StatefulWidget {
  const PulseCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.selected = false,
    this.elevated = false,
    this.fillHeight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool selected;
  final bool elevated;
  /// When true (e.g. equal-height Diagnostics cards), expand to the parent's
  /// max height. Only safe under bounded height (IntrinsicHeight + stretch).
  final bool fillHeight;

  @override
  State<PulseCard> createState() => _PulseCardState();
}

class _PulseCardState extends State<PulseCard> with SafeHoverState {
  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final highlighted = interactive && (hover || widget.selected);
    final bg = widget.selected
        ? PulseTokens.accentSoft
        : highlighted
            ? PulseTokens.surfaceHover
            : widget.elevated
                ? PulseTokens.surfaceElevated
                : PulseTokens.surface;
    final border = widget.selected
        ? PulseTokens.accent.withValues(alpha: 0.4)
        : PulseTokens.stroke.withValues(alpha: highlighted ? 0.8 : 0.5);

    final content = Padding(
      padding: widget.padding ?? const EdgeInsets.all(PulseTokens.spaceMd),
      child: widget.child,
    );

    final animate = !MediaQuery.disableAnimationsOf(context);
    // No hover transform — moving hit-test bounds causes enter/exit loops.
    // No nested MouseRegion + InkWell — use InkWell.onHover only.
    return AnimatedContainer(
      duration: animate ? PulseTokens.motionNormal : Duration.zero,
      curve: PulseTokens.motionCurve,
      width: double.infinity,
      height: widget.fillHeight ? double.infinity : null,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PulseTokens.radiusCard),
        border: Border.all(color: border),
        boxShadow: highlighted
            ? PulseTokens.elevationLift
            : widget.elevated
                ? PulseTokens.elevation1
                : PulseTokens.elevationSoft,
      ),
      child: interactive
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onHover: setHovered,
                borderRadius: BorderRadius.circular(PulseTokens.radiusCard),
                splashColor: PulseTokens.accent.withValues(alpha: 0.08),
                highlightColor: PulseTokens.accent.withValues(alpha: 0.04),
                mouseCursor: SystemMouseCursors.click,
                child: content,
              ),
            )
          : content,
    );
  }
}
