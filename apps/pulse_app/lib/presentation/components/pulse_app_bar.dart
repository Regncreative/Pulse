import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import 'connection_indicator.dart';
import 'safe_hover.dart';

class PulseAppBar extends StatelessWidget {
  const PulseAppBar({
    super.key,
    required this.title,
    required this.connectionState,
    required this.connectionLabel,
    this.actions,
    this.searchHint,
  });

  final String title;
  final IpcConnectionState connectionState;
  final String connectionLabel;
  final List<Widget>? actions;
  final String? searchHint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        PulseTokens.pagePadX,
        12,
        28,
        12,
      ),
      decoration: BoxDecoration(
        color: PulseTokens.canvas.withValues(alpha: 0.35),
        border: const Border(
          bottom: BorderSide(color: PulseTokens.strokeSubtle),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        letterSpacing: -0.3,
                      ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConnectionIndicator(
                      state: connectionState,
                      label: connectionLabel,
                      compact: MediaQuery.sizeOf(context).width < 1100,
                    ),
                  ),
                ),
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ...actions!,
                ],
              ],
            ),
          ),
          if (searchHint != null) ...[
            const SizedBox(height: 12),
            _SearchField(hint: searchHint!),
          ],
        ],
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.hint});
  final String hint;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> with SafeHoverState {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: AnimatedContainer(
        duration: PulseTokens.motionFast,
        height: 36,
        decoration: BoxDecoration(
          color: hover
              ? PulseTokens.surfaceHover.withValues(alpha: 0.35)
              : PulseTokens.surface,
          borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
          border: Border.all(
            color: PulseTokens.stroke.withValues(alpha: 0.65),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              LucideIcons.search,
              size: 15,
              color: PulseTokens.textDisabled,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PulseTokens.textTertiary,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Unavailable',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: PulseTokens.textDisabled,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
