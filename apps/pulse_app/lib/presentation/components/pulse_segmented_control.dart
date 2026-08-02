import 'package:flutter/material.dart';

import '../../app/theme/pulse_theme.dart';
import 'safe_hover.dart';

/// Windows 11–style segmented control using Pulse accent tokens.
///
/// Selected: accentSoft fill, accent border/label (matches Timeline chips /
/// Connected badge language). Unselected: transparent fill, stroke border.
class PulseSegmentedControl<T> extends StatelessWidget {
  const PulseSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<PulseSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  static const double _height = 36;
  static const double _radius = 12;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final control = DecoratedBox(
          decoration: BoxDecoration(
            color: PulseTokens.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: PulseTokens.stroke.withValues(alpha: 0.75)),
          ),
          child: SizedBox(
            height: _height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: 18,
                      color: PulseTokens.strokeSubtle,
                    ),
                  _SegmentButton<T>(
                    segment: segments[i],
                    selected: segments[i].value == selected,
                    onPressed: segments[i].enabled
                        ? () => onChanged(segments[i].value)
                        : null,
                  ),
                ],
              ],
            ),
          ),
        );

        if (constraints.maxWidth.isFinite &&
            constraints.maxWidth < 360 &&
            constraints.maxWidth > 0) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: control,
          );
        }
        return control;
      },
    );
  }
}

class PulseSegment<T> {
  const PulseSegment({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

class _SegmentButton<T> extends StatefulWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.onPressed,
  });

  final PulseSegment<T> segment;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  State<_SegmentButton<T>> createState() => _SegmentButtonState<T>();
}

class _SegmentButtonState<T> extends State<_SegmentButton<T>>
    with SafeHoverState {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final selected = widget.selected;

    Color bg;
    Color fg;
    Color border;

    if (!enabled) {
      bg = Colors.transparent;
      fg = PulseTokens.textDisabled;
      border = Colors.transparent;
    } else if (selected) {
      bg = _pressed
          ? Color.lerp(PulseTokens.accentSoft, PulseTokens.accent, 0.18)!
          : PulseTokens.accentSoft;
      fg = PulseTokens.accent;
      border = PulseTokens.accent.withValues(alpha: 0.45);
    } else if (_pressed) {
      bg = PulseTokens.accent.withValues(alpha: 0.12);
      fg = PulseTokens.textPrimary;
      border = Colors.transparent;
    } else if (hover) {
      bg = PulseTokens.accent.withValues(alpha: 0.08);
      fg = PulseTokens.textPrimary;
      border = Colors.transparent;
    } else {
      bg = Colors.transparent;
      fg = PulseTokens.textSecondary;
      border = Colors.transparent;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onPressed,
        onHover: enabled ? setHovered : null,
        onHighlightChanged: enabled
            ? (v) => setState(() => _pressed = v)
            : null,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : PulseTokens.motionFast,
          curve: PulseTokens.motionCurve,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Text(
            widget.segment.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
          ),
        ),
      ),
    );
  }
}
