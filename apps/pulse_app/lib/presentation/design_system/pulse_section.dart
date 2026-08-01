import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';
import '../components/pulse_section_header.dart';

/// Collapsible section with title, optional subtitle, chevron, and soft divider.
///
/// Expansion state is controlled by the parent. When [storageKey] is set, the
/// parent is expected to persist the preference keyed by that string.
class PulseSection extends StatelessWidget {
  const PulseSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    required this.expanded,
    required this.onExpandedChanged,
    this.storageKey,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  /// Optional persistence key — parent owns SharedPreferences / settings.
  final String? storageKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.pulseTheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => onExpandedChanged(!expanded),
          borderRadius: BorderRadius.circular(theme.radiusMd),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: theme.spaceSm,
              horizontal: 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: theme.textPrimary,
                        ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        SizedBox(height: theme.spaceXs),
                        Text(
                          subtitle!,
                          style: textTheme.bodySmall?.copyWith(
                            color: theme.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  SizedBox(width: theme.spaceSm),
                  trailing!,
                ],
                SizedBox(width: theme.spaceXs),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: theme.motionNormal,
                  curve: theme.motionCurve,
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: theme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: theme.motionNormal,
          curve: theme.motionCurve,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: EdgeInsets.only(
                    top: theme.spaceSm,
                    bottom: theme.spaceMd,
                  ),
                  child: child,
                )
              : const SizedBox.shrink(),
        ),
        SoftDivider(),
      ],
    );
  }
}
