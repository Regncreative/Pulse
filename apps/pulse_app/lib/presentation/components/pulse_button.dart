import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';
import 'safe_hover.dart';

enum PulseButtonVariant { primary, secondary, ghost, danger }

class PulseButton extends StatefulWidget {
  const PulseButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = PulseButtonVariant.primary,
    this.loading = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final PulseButtonVariant variant;
  final bool loading;
  final bool expanded;

  @override
  State<PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<PulseButton> with SafeHoverState {
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final colors = _palette(widget.variant, enabled, hover);

    final child = Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.$2,
            ),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 16, color: colors.$2),
        if (widget.loading || widget.icon != null) const SizedBox(width: 8),
        Text(
          widget.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.$2,
              ),
        ),
      ],
    );

    // Single pointer annotation via InkWell — do not nest MouseRegion.
    return AnimatedContainer(
      duration: PulseTokens.motionFast,
      curve: PulseTokens.motionCurve,
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        border: Border.all(color: colors.$3),
        boxShadow: widget.variant == PulseButtonVariant.primary && enabled
            ? [
                BoxShadow(
                  color: PulseTokens.accent.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? widget.onPressed : null,
          onHover: enabled ? setHovered : null,
          borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: child,
          ),
        ),
      ),
    );
  }

  /// bg, fg, border
  (Color, Color, Color) _palette(
    PulseButtonVariant variant,
    bool enabled,
    bool hovered,
  ) {
    if (!enabled) {
      return (
        PulseTokens.surface,
        PulseTokens.textDisabled,
        PulseTokens.strokeSubtle,
      );
    }
    switch (variant) {
      case PulseButtonVariant.primary:
        return (
          hovered ? const Color(0xFF78D6FF) : PulseTokens.accent,
          const Color(0xFF001B26),
          Colors.transparent,
        );
      case PulseButtonVariant.secondary:
        return (
          hovered ? PulseTokens.surfaceHover : PulseTokens.surfaceElevated,
          PulseTokens.textPrimary,
          PulseTokens.stroke,
        );
      case PulseButtonVariant.ghost:
        return (
          hovered ? PulseTokens.surfaceHover : Colors.transparent,
          PulseTokens.textSecondary,
          Colors.transparent,
        );
      case PulseButtonVariant.danger:
        return (
          hovered
              ? PulseTokens.error.withValues(alpha: 0.22)
              : PulseTokens.error.withValues(alpha: 0.14),
          PulseTokens.error,
          PulseTokens.error.withValues(alpha: 0.35),
        );
    }
  }
}
