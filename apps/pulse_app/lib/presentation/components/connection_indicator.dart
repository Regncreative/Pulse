import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../utils/pulse_user_errors.dart';
import 'pulse_badge.dart';

class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({
    super.key,
    required this.state,
    required this.label,
    this.compact = false,
  });

  final IpcConnectionState state;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tone = switch (state) {
      IpcConnectionState.connected => PulseBadgeTone.success,
      IpcConnectionState.connecting => PulseBadgeTone.warning,
      IpcConnectionState.error => PulseBadgeTone.error,
      IpcConnectionState.disconnected => PulseBadgeTone.neutral,
    };

    return Tooltip(
      message: PulseUserErrors.connectionHint(state),
      waitDuration: const Duration(milliseconds: 400),
      child: _AnimatedConnectionBadge(
        state: state,
        tone: tone,
        label: compact ? _shortLabel(state) : label,
        compact: compact,
      ),
    );
  }

  static String _shortLabel(IpcConnectionState state) {
    return switch (state) {
      IpcConnectionState.connected => 'Connected',
      IpcConnectionState.connecting => 'Connecting',
      IpcConnectionState.error => 'Offline',
      IpcConnectionState.disconnected => 'Offline',
    };
  }
}

class _AnimatedConnectionBadge extends StatefulWidget {
  const _AnimatedConnectionBadge({
    required this.state,
    required this.tone,
    required this.label,
    required this.compact,
  });

  final IpcConnectionState state;
  final PulseBadgeTone tone;
  final String label;
  final bool compact;

  @override
  State<_AnimatedConnectionBadge> createState() =>
      _AnimatedConnectionBadgeState();
}

class _AnimatedConnectionBadgeState extends State<_AnimatedConnectionBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _AnimatedConnectionBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final disable =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.state == IpcConnectionState.connecting && !disable) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  IconData get _icon => switch (widget.state) {
        IpcConnectionState.connected => LucideIcons.radio,
        IpcConnectionState.connecting => LucideIcons.loader2,
        IpcConnectionState.error => LucideIcons.unplug,
        IpcConnectionState.disconnected => LucideIcons.unplug,
      };

  @override
  Widget build(BuildContext context) {
    final badge = PulseBadge(
      label: widget.label,
      tone: widget.tone,
      compact: widget.compact,
      iconWidget: widget.state == IpcConnectionState.connecting
          ? AnimatedBuilder(
              animation: _spin,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _spin.value * math.pi * 2,
                  child: child,
                );
              },
              child: Icon(
                _icon,
                size: widget.compact ? 12 : 13,
                color: _badgeFg(widget.tone),
              ),
            )
          : Icon(
              _icon,
              size: widget.compact ? 12 : 13,
              color: _badgeFg(widget.tone),
            ),
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: badge,
    );
  }

  Color _badgeFg(PulseBadgeTone tone) {
    return switch (tone) {
      PulseBadgeTone.success => PulseTokens.success,
      PulseBadgeTone.warning => PulseTokens.severityWarning,
      PulseBadgeTone.error => PulseTokens.error,
      PulseBadgeTone.info || PulseBadgeTone.accent => PulseTokens.accent,
      PulseBadgeTone.neutral => PulseTokens.textSecondary,
    };
  }
}

class ConnectionDot extends StatefulWidget {
  const ConnectionDot({super.key, required this.state, this.size = 8});

  final IpcConnectionState state;
  final double size;

  @override
  State<ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<ConnectionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ConnectionDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncAnimation();
  }

  void _syncAnimation() {
    // Pulse only while connecting — connected is a calm steady dot.
    if (widget.state == IpcConnectionState.connecting) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.state) {
      IpcConnectionState.connected => PulseTokens.success,
      IpcConnectionState.connecting => PulseTokens.severityWarning,
      IpcConnectionState.error => PulseTokens.error,
      IpcConnectionState.disconnected => PulseTokens.textDisabled,
    };

    final pulse = widget.state == IpcConnectionState.connecting;

    return SizedBox(
      width: widget.size + 10,
      height: widget.size + 10,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = pulse ? _controller.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (pulse)
                Container(
                  width: widget.size + (t * 10),
                  height: widget.size + (t * 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.35 * (1 - t)),
                      width: 1.2,
                    ),
                  ),
                ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3 + (t * 0.25)),
                      blurRadius: 5 + (t * 6),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
