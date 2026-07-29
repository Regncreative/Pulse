import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pulse_protocol/pulse_wire.dart';

import '../../../app/theme/pulse_theme.dart';
import '../../../presentation/components/pulse_badge.dart';
import '../../../presentation/components/pulse_focus.dart';
import '../../../presentation/components/safe_hover.dart';
import '../timeline_display.dart';

/// Compact Timeline card — title + short summary + meta only.
class TimelineEventTile extends StatefulWidget {
  const TimelineEventTile({
    super.key,
    required this.event,
    required this.isFirst,
    required this.isLast,
    this.selected = false,
    this.emphasize = false,
    this.animationIndex = 0,
    this.onTap,
  });

  final TimelineEvent event;
  final bool isFirst;
  final bool isLast;
  final bool selected;
  final bool emphasize;
  final int animationIndex;
  final VoidCallback? onTap;

  @override
  State<TimelineEventTile> createState() => _TimelineEventTileState();
}

class _TimelineEventTileState extends State<TimelineEventTile>
    with TickerProviderStateMixin, SafeHoverState {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: PulseTokens.motionSlow,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _enter.value = 1;
        return;
      }
      final delay = Duration(milliseconds: 24 + (widget.animationIndex * 36));
      Future<void>.delayed(delay, () {
        if (mounted) _enter.forward();
      });
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.event.severityVisual;
    final highlighted = hover || widget.selected;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _enter, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _enter, curve: PulseTokens.motionEmphasized),
        ),
        child: IntrinsicHeight(
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.isLast ? 0 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EventRail(
                  color: style.color,
                  isFirst: widget.isFirst,
                  isLast: widget.isLast,
                  selected: widget.selected,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PulseFocus(
                    onPressed: widget.onTap,
                    borderRadius: BorderRadius.circular(PulseTokens.radiusCard),
                    child: AnimatedContainer(
                      duration: PulseTokens.motionNormal,
                      curve: PulseTokens.motionCurve,
                      decoration: BoxDecoration(
                        color: widget.selected
                            ? Color.alphaBlend(
                                style.soft.withValues(alpha: 0.55),
                                PulseTokens.surfaceElevated,
                              )
                            : hover
                                ? PulseTokens.surfaceElevated
                                : PulseTokens.surface.withValues(alpha: 0.92),
                        borderRadius:
                            BorderRadius.circular(PulseTokens.radiusCard),
                        border: Border.all(
                          color: widget.selected
                              ? style.color.withValues(alpha: 0.48)
                              : hover
                                  ? PulseTokens.strokeStrong
                                      .withValues(alpha: 0.65)
                                  : PulseTokens.stroke.withValues(alpha: 0.4),
                          width: widget.selected ? 1.2 : 1,
                        ),
                        boxShadow: highlighted
                            ? PulseTokens.elevationLift
                            : PulseTokens.elevationSoft,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: widget.onTap,
                          onHover: setHovered,
                          borderRadius:
                              BorderRadius.circular(PulseTokens.radiusCard),
                          splashColor: style.color.withValues(alpha: 0.07),
                          highlightColor: style.color.withValues(alpha: 0.03),
                          mouseCursor: SystemMouseCursors.click,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 3,
                                  height: 28,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    color: style.color,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (widget.emphasize) ...[
                                        Text(
                                          'LATEST',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: style.color,
                                                letterSpacing: 0.85,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                      ],
                                      Text(
                                        widget.event.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontSize: 14.5,
                                              height: 1.3,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.event.displaySummary,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: PulseTokens.textSecondary,
                                              height: 1.35,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.event.actionGuidance,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: widget.event.actionRequired
                                                  ? PulseTokens.severityWarning
                                                  : PulseTokens.textTertiary,
                                              height: 1.3,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          _MetaChip(
                                            icon: LucideIcons.clock,
                                            label:
                                                widget.event.relativeTimeLabel,
                                          ),
                                          Icon(
                                            LucideIcons.dot,
                                            size: 12,
                                            color: PulseTokens.textDisabled,
                                          ),
                                          Text(
                                            widget.event.displayChannel,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          PulseBadge(
                                            label: style.label,
                                            tone: style.tone,
                                            compact: true,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                AnimatedOpacity(
                                  duration: PulseTokens.motionFast,
                                  opacity: highlighted ? 1 : 0.35,
                                  child: Icon(
                                    LucideIcons.chevronRight,
                                    size: 15,
                                    color: PulseTokens.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: PulseTokens.textTertiary),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EventRail extends StatelessWidget {
  const _EventRail({
    required this.color,
    required this.isFirst,
    required this.isLast,
    required this.selected,
  });

  final Color color;
  final bool isFirst;
  final bool isLast;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final nodeSize = selected ? 11.0 : 9.0;
    return SizedBox(
      width: 22,
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 2,
                color: isFirst
                    ? Colors.transparent
                    : PulseTokens.stroke.withValues(alpha: 0.5),
              ),
            ),
          ),
          Container(
            width: nodeSize,
            height: nodeSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: PulseTokens.canvas,
                width: selected ? 2.5 : 2,
              ),
            ),
          ),
          Expanded(
            flex: isLast ? 0 : 1,
            child: isLast
                ? const SizedBox(height: 6)
                : Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 2,
                      color: PulseTokens.stroke.withValues(alpha: 0.5),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
