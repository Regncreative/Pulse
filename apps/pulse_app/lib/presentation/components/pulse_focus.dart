import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/pulse_theme.dart';

/// Keyboard-friendly focus ring matching Windows 11 focus visuals.
class PulseFocus extends StatefulWidget {
  const PulseFocus({
    super.key,
    required this.child,
    this.onPressed,
    this.borderRadius,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final BorderRadius? borderRadius;
  final bool enabled;

  @override
  State<PulseFocus> createState() => _PulseFocusState();
}

class _PulseFocusState extends State<PulseFocus> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.borderRadius ?? BorderRadius.circular(PulseTokens.radiusCard);

    return FocusableActionDetector(
      enabled: widget.enabled && widget.onPressed != null,
      onShowFocusHighlight: (v) {
        if (_focused == v) return;
        _focused = v;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {});
        });
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: AnimatedContainer(
        duration: PulseTokens.motionFast,
        curve: PulseTokens.motionCurve,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: _focused
                ? PulseTokens.focusRing.withValues(alpha: 0.85)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: PulseTokens.focusRing.withValues(alpha: 0.22),
                    blurRadius: 0,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
