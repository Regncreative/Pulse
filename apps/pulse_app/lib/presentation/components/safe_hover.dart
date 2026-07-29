import 'package:flutter/widgets.dart';

/// Hover helpers that never call [State.setState] during MouseTracker updates.
///
/// Calling setState from MouseRegion onEnter/onExit while Flutter is inside
/// `_deviceUpdatePhase` triggers:
/// `!_debugDuringDeviceUpdate': is not true`
/// and can recurse into an infinite exception loop — especially when hover
/// also changes hit-test geometry (e.g. transforms).
mixin SafeHoverState<T extends StatefulWidget> on State<T> {
  bool hover = false;
  bool _hoverFrameScheduled = false;

  void setHovered(bool value) {
    if (hover == value) return;
    hover = value;
    if (_hoverFrameScheduled) return;
    _hoverFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hoverFrameScheduled = false;
      if (!mounted) return;
      setState(() {});
    });
  }
}
