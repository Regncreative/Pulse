import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../app/theme/pulse_theme.dart';
import '../../application/assistant_controller.dart';
import '../components/pulse_focus.dart';
import '../components/safe_hover.dart';

/// Primary bottom-right Assistant trigger — discoverable, not a chat FAB.
class AssistantEntryButton extends StatefulWidget {
  const AssistantEntryButton({super.key});

  @override
  State<AssistantEntryButton> createState() => _AssistantEntryButtonState();
}

class _AssistantEntryButtonState extends State<AssistantEntryButton>
    with SafeHoverState {
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final open = context.select<AssistantController, bool>((c) => c.panelOpen);
    final tooltip = open ? 'Close Assistant' : 'Open Pulse Assistant';

    final bg = open
        ? PulseTokens.surfaceElevated
        : (hover
            ? PulseTokens.accent.withValues(alpha: 0.92)
            : PulseTokens.accent);
    final fg = open ? PulseTokens.accent : Colors.white;
    final borderColor = open
        ? PulseTokens.accent
        : PulseTokens.accent.withValues(alpha: hover ? 1 : 0.85);
    final radius = BorderRadius.circular(PulseTokens.radiusXl);

    void toggle() => context.read<AssistantController>().togglePanel();

    return Semantics(
      button: true,
      label: tooltip,
      toggled: open,
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: PulseFocus(
          onPressed: toggle,
          borderRadius: radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: toggle,
              onHover: setHovered,
              borderRadius: radius,
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : PulseTokens.motionFast,
                curve: PulseTokens.motionCurve,
                padding: const EdgeInsets.fromLTRB(16, 12, 18, 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: radius,
                  border: Border.all(color: borderColor, width: open ? 1.5 : 1),
                  boxShadow: [
                    BoxShadow(
                      color: PulseTokens.accent.withValues(
                        alpha: open ? 0.22 : (hover ? 0.38 : 0.28),
                      ),
                      blurRadius: open ? 16 : 20,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: open
                            ? PulseTokens.accentSoft
                            : Colors.white.withValues(alpha: 0.16),
                        borderRadius:
                            BorderRadius.circular(PulseTokens.radiusMd),
                      ),
                      child: Icon(
                        open ? LucideIcons.x : LucideIcons.sparkles,
                        size: 16,
                        color: fg,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Assistant',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            fontSize: 14,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
