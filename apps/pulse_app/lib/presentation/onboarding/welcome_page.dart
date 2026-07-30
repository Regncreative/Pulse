import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/pulse_theme.dart';
import '../components/pulse_button.dart';
import '../components/pulse_empty_state.dart';

/// Short first-launch introduction — skippable, local-only.
class WelcomePage extends StatefulWidget {
  const WelcomePage({
    super.key,
    required this.onFinished,
  });

  final VoidCallback onFinished;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  int _step = 0;

  static const _pages = [
    _WelcomeSlide(
      icon: LucideIcons.listTree,
      title: 'Timeline',
      body:
          'See what Windows is doing in plain language — service starts, warnings, and recoveries as a readable event stream.',
    ),
    _WelcomeSlide(
      icon: LucideIcons.heartPulse,
      title: 'System Health',
      body:
          'Watch live CPU, memory, GPU, disk, and network — aligned with Task Manager where Windows APIs allow.',
    ),
    _WelcomeSlide(
      icon: LucideIcons.activity,
      title: 'Diagnostics',
      body:
          'When something looks off, check service status, IPC health, and the event pipeline — all data stays on this PC.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final slide = _pages[_step];
    final last = _step == _pages.length - 1;

    return Material(
      color: PulseTokens.canvas,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PulseTokens.spaceXl,
                vertical: PulseTokens.space2xl,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const PulseBrandMark(size: 88),
                  const SizedBox(height: PulseTokens.spaceLg),
                  Text(
                    'Welcome to Pulse',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontSize: 24,
                          letterSpacing: -0.4,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'See what Windows is really doing — observation only, no cloud.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: PulseTokens.textSecondary,
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: PulseTokens.space2xl),
                  AnimatedSwitcher(
                    duration: PulseTokens.motionNormal,
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _SlideCard(slide: slide),
                    ),
                  ),
                  const SizedBox(height: PulseTokens.spaceLg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        AnimatedContainer(
                          duration: PulseTokens.motionFast,
                          width: i == _step ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _step
                                ? PulseTokens.accent
                                : PulseTokens.stroke,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: PulseTokens.space2xl),
                  Row(
                    children: [
                      Expanded(
                        child: PulseButton(
                          label: 'Skip',
                          variant: PulseButtonVariant.ghost,
                          onPressed: widget.onFinished,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PulseButton(
                          label: last ? 'Get started' : 'Next',
                          onPressed: () {
                            if (last) {
                              widget.onFinished();
                            } else {
                              setState(() => _step++);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeSlide {
  const _WelcomeSlide({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.slide});
  final _WelcomeSlide slide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: PulseTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(PulseTokens.radiusLg),
        border: Border.all(color: PulseTokens.stroke.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: PulseTokens.accentSoft,
              borderRadius: BorderRadius.circular(PulseTokens.radiusIconWell),
            ),
            child: Icon(slide.icon, size: 18, color: PulseTokens.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slide.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  slide.body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PulseTokens.textSecondary,
                        height: 1.5,
                        fontSize: 13.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
