import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';

enum PulseBadgeTone { neutral, accent, success, warning, error, info }

class PulseBadge extends StatelessWidget {
  const PulseBadge({
    super.key,
    required this.label,
    this.tone = PulseBadgeTone.neutral,
    this.icon,
    this.iconWidget,
    this.compact = false,
  });

  final String label;
  final PulseBadgeTone tone;
  final IconData? icon;
  final Widget? iconWidget;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(tone);
    final leading = iconWidget ??
        (icon != null
            ? Icon(icon, size: compact ? 12 : 13, color: colors.$2)
            : null);

    // Never use LayoutBuilder here — badges appear inside IntrinsicHeight
    // (timeline tiles). LayoutBuilder cannot compute dry layout and throws,
    // which then cascades into MouseTracker assertion floods.
    return AnimatedContainer(
      duration: PulseTokens.motionNormal,
      curve: PulseTokens.motionCurve,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(PulseTokens.radiusPill),
        border: Border.all(color: colors.$2.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading,
            SizedBox(width: compact ? 5 : 6),
          ],
          // Cap width instead of LayoutBuilder — badges must stay safe inside
          // IntrinsicHeight (timeline) while still ellipsizing long labels.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 140 : 220),
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.$2,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 11 : 12,
                    height: 1.1,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static (Color, Color) _colors(PulseBadgeTone tone) {
    switch (tone) {
      case PulseBadgeTone.accent:
        return (PulseTokens.accentSoft, PulseTokens.accent);
      case PulseBadgeTone.success:
        return (
          PulseTokens.success.withValues(alpha: 0.14),
          PulseTokens.success,
        );
      case PulseBadgeTone.warning:
        return (
          PulseTokens.severityWarning.withValues(alpha: 0.14),
          PulseTokens.severityWarning,
        );
      case PulseBadgeTone.error:
        return (
          PulseTokens.error.withValues(alpha: 0.14),
          PulseTokens.error,
        );
      case PulseBadgeTone.info:
        return (
          PulseTokens.info.withValues(alpha: 0.14),
          PulseTokens.info,
        );
      case PulseBadgeTone.neutral:
        return (PulseTokens.surfaceHover, PulseTokens.textSecondary);
    }
  }
}
