import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/pulse_theme.dart';
import 'pulse_button.dart';

class PulseEmptyState extends StatelessWidget {
  const PulseEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.useBrandIllustration = false,
  });

  final IconData? icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool useBrandIllustration;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PulseTokens.spaceXl,
            vertical: PulseTokens.space2xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.96, end: 1),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : PulseTokens.motionSlow,
                curve: PulseTokens.motionCurve,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: useBrandIllustration || icon == null
                    ? const PulseBrandMark(size: 96)
                    : _IconPlate(icon: icon!),
              ),
              const SizedBox(height: PulseTokens.spaceLg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 22,
                      letterSpacing: -0.3,
                      height: 1.25,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PulseTokens.textSecondary,
                      height: 1.6,
                      fontSize: 14,
                    ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: PulseTokens.spaceLg),
                PulseButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  variant: PulseButtonVariant.secondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconPlate extends StatelessWidget {
  const _IconPlate({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: PulseTokens.accentSoft,
        borderRadius: BorderRadius.circular(PulseTokens.radiusXl),
        border: Border.all(color: PulseTokens.accent.withValues(alpha: 0.2)),
      ),
      child: Icon(icon, size: 32, color: PulseTokens.accent),
    );
  }
}

/// Official Pulse tile for empty / onboarding surfaces.
class PulseBrandMark extends StatelessWidget {
  const PulseBrandMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.92,
            height: size * 0.92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: PulseTokens.accent.withValues(alpha: 0.12),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.18),
            child: SvgPicture.asset(
              'assets/branding/app_icon.svg',
              width: size * 0.62,
              height: size * 0.62,
            ),
          ),
        ],
      ),
    );
  }
}
