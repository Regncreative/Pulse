import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/theme/pulse_theme.dart';
import 'safe_hover.dart';

/// Native-feeling custom title bar that blends into Pulse chrome.
class PulseTitleBar extends StatefulWidget {
  const PulseTitleBar({super.key});

  @override
  State<PulseTitleBar> createState() => _PulseTitleBarState();
}

class _PulseTitleBarState extends State<PulseTitleBar> with WindowListener {
  bool _maximized = false;
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refresh();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    final maximized = await windowManager.isMaximized();
    final focused = await windowManager.isFocused();
    if (!mounted) return;
    if (_maximized == maximized && _focused == focused) return;
    setState(() {
      _maximized = maximized;
      _focused = focused;
    });
  }

  @override
  void onWindowMaximize() => _refresh();

  @override
  void onWindowUnmaximize() => _refresh();

  @override
  void onWindowRestore() => _refresh();

  @override
  void onWindowFocus() => _refresh();

  @override
  void onWindowBlur() => _refresh();

  @override
  Widget build(BuildContext context) {
    final fg = _focused ? PulseTokens.textPrimary : PulseTokens.textTertiary;

    return DragToMoveArea(
      child: Container(
        height: 40,
        decoration: const BoxDecoration(
          color: PulseTokens.sidebarSolid,
          border: Border(
            bottom: BorderSide(color: PulseTokens.strokeSubtle),
          ),
        ),
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/branding/mark.svg',
              width: 16,
              height: 16,
            ),
            const SizedBox(width: 10),
            Text(
              'Pulse',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    fontSize: 13,
                  ),
            ),
            const Spacer(),
            _CaptionButton(
              tooltip: 'Minimize',
              onPressed: windowManager.minimize,
              icon: Icons.remove,
              color: fg,
            ),
            _CaptionButton(
              tooltip: _maximized ? 'Restore' : 'Maximize',
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              icon: _maximized ? Icons.filter_none : Icons.crop_square,
              iconSize: _maximized ? 13 : 14,
              color: fg,
            ),
            _CaptionButton(
              tooltip: 'Close',
              isClose: true,
              onPressed: windowManager.close,
              icon: Icons.close,
              color: fg,
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    required this.color,
    this.iconSize = 16,
    this.isClose = false,
  });

  final IconData icon;
  final Future<void> Function() onPressed;
  final String tooltip;
  final Color color;
  final double iconSize;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> with SafeHoverState {
  @override
  Widget build(BuildContext context) {
    final bg = !hover
        ? Colors.transparent
        : widget.isClose
            ? const Color(0xFFE81123)
            : PulseTokens.surfaceHover.withValues(alpha: 0.7);
    final iconColor =
        widget.isClose && hover ? Colors.white : widget.color;

    // Avoid Tooltip + MouseRegion nesting — Tooltip already tracks the pointer.
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onPressed(),
        child: MouseRegion(
          onEnter: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: AnimatedContainer(
            duration: PulseTokens.motionFast,
            width: 46,
            height: 40,
            color: bg,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
