import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../application/service_lifecycle_controller.dart';
import '../../app/theme/pulse_theme.dart';
import '../../platform/pulse_service_scm.dart';
import 'pulse_badge.dart';
import 'pulse_button.dart';
import 'pulse_card.dart';
import '../utils/pulse_snack.dart';
import '../utils/pulse_user_errors.dart';

/// Start / Stop / Restart / Repair controls shared by Diagnostics + offline UX.
class ServiceLifecycleControls extends StatelessWidget {
  const ServiceLifecycleControls({
    super.key,
    this.compact = false,
    this.showStopRestart = true,
  });

  final bool compact;
  final bool showStopRestart;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action, {
    required String fallbackOk,
    bool confirmStop = false,
    bool confirmRestart = false,
  }) async {
    final life = context.read<ServiceLifecycleController>();
    if (confirmStop) {
      final ok = await _confirm(
        context,
        title: 'Stop PulseService?',
        body:
            'Timeline and System Health will go offline until the service starts again.',
        confirmLabel: 'Stop service',
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    if (confirmRestart) {
      final ok = await _confirm(
        context,
        title: 'Restart PulseService?',
        body:
            'Pulse will disconnect briefly while Windows restarts the service.',
        confirmLabel: 'Restart service',
      );
      if (!ok || !context.mounted) return;
    }

    try {
      await action();
      if (!context.mounted) return;
      final msg = life.lastSuccess ?? fallbackOk;
      PulseSnack.success(context, msg);
    } catch (e) {
      if (!context.mounted) return;
      PulseSnack.error(context, PulseUserErrors.fromObject(e));
    }
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: PulseTokens.surfaceElevated,
          title: Text(title),
          content: Text(
            body,
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: PulseTokens.textSecondary,
                  height: 1.5,
                ),
          ),
          actions: [
            PulseButton(
              label: 'Cancel',
              variant: PulseButtonVariant.ghost,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            PulseButton(
              label: confirmLabel,
              variant: danger
                  ? PulseButtonVariant.danger
                  : PulseButtonVariant.primary,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final life = context.watch<ServiceLifecycleController>();
    final busy = life.actionBusy || life.isTransitioning;

    final buttons = <Widget>[
      if (life.canRepair || life.state == PulseServiceScmState.notInstalled)
        PulseButton(
          label: 'Repair / Install',
          icon: LucideIcons.wrench,
          loading: busy && life.state == PulseServiceScmState.notInstalled,
          onPressed: busy
              ? null
              : () => _run(
                    context,
                    life.repairInstall,
                    fallbackOk: 'PulseService installed and started',
                  ),
        ),
      if (life.canStart ||
          life.state == PulseServiceScmState.stopped ||
          life.state == PulseServiceScmState.unknown)
        PulseButton(
          label: 'Start',
          icon: LucideIcons.play,
          loading: busy &&
              (life.state == PulseServiceScmState.stopped ||
                  life.state == PulseServiceScmState.unknown ||
                  life.state == PulseServiceScmState.startPending),
          onPressed: life.canStart
              ? () => _run(
                    context,
                    life.startService,
                    fallbackOk: 'PulseService started',
                  )
              : null,
        ),
      if (showStopRestart &&
          (life.canStop || life.state == PulseServiceScmState.running))
        PulseButton(
          label: 'Stop',
          icon: LucideIcons.square,
          variant: PulseButtonVariant.danger,
          loading: busy && life.state == PulseServiceScmState.stopPending,
          onPressed: life.canStop
              ? () => _run(
                    context,
                    life.stopService,
                    fallbackOk: 'PulseService stopped',
                    confirmStop: true,
                  )
              : null,
        ),
      if (showStopRestart &&
          (life.canRestart || life.state == PulseServiceScmState.running))
        PulseButton(
          label: 'Restart',
          icon: LucideIcons.refreshCw,
          variant: PulseButtonVariant.secondary,
          loading: busy && life.state == PulseServiceScmState.startPending,
          onPressed: life.canRestart
              ? () => _run(
                    context,
                    life.restartService,
                    fallbackOk: 'PulseService restarted',
                    confirmRestart: true,
                  )
              : null,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Windows service',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: PulseTokens.textSecondary,
                  ),
            ),
            const SizedBox(width: 10),
            PulseBadge(
              label: life.statusLabel,
              tone: switch (life.state) {
                PulseServiceScmState.running => PulseBadgeTone.success,
                PulseServiceScmState.stopped ||
                PulseServiceScmState.notInstalled =>
                  PulseBadgeTone.warning,
                PulseServiceScmState.startPending ||
                PulseServiceScmState.stopPending =>
                  PulseBadgeTone.info,
                PulseServiceScmState.unknown => PulseBadgeTone.neutral,
              },
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          Text(
            life.recoveryMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.textTertiary,
                  height: 1.45,
                ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: buttons,
        ),
        if (life.lastError != null) ...[
          const SizedBox(height: 10),
          Text(
            life.lastError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.error,
                  height: 1.4,
                ),
          ),
        ],
      ],
    );
  }
}

/// Offline empty / recovery surface with a primary Start/Repair CTA.
class ServiceOfflineRecovery extends StatelessWidget {
  const ServiceOfflineRecovery({
    super.key,
    required this.titleFallback,
    this.showFullControls = false,
  });

  final String titleFallback;
  final bool showFullControls;

  @override
  Widget build(BuildContext context) {
    final life = context.watch<ServiceLifecycleController>();
    final busy = life.actionBusy || life.isTransitioning;
    final actionLabel = life.primaryActionLabel;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PulseTokens.spaceXl,
            vertical: PulseTokens.space2xl,
          ),
          child: PulseCard(
            elevated: true,
            padding: const EdgeInsets.all(PulseTokens.spaceXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  life.state == PulseServiceScmState.running
                      ? titleFallback
                      : life.recoveryTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 22,
                        letterSpacing: -0.3,
                        height: 1.25,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  life.recoveryMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PulseTokens.textSecondary,
                        height: 1.6,
                        fontSize: 14,
                      ),
                ),
                const SizedBox(height: PulseTokens.spaceLg),
                if (actionLabel != null)
                  PulseButton(
                    label: actionLabel,
                    icon: life.state == PulseServiceScmState.notInstalled
                        ? LucideIcons.wrench
                        : LucideIcons.play,
                    loading: busy,
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await life.runPrimaryRecoveryAction();
                              if (!context.mounted) return;
                              PulseSnack.success(
                                context,
                                life.lastSuccess ?? 'PulseService updated',
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              PulseSnack.error(
                                context,
                                PulseUserErrors.fromObject(e),
                              );
                            }
                          },
                  ),
                if (showFullControls) ...[
                  const SizedBox(height: PulseTokens.spaceLg),
                  Divider(height: 1, color: PulseTokens.strokeSubtle),
                  const SizedBox(height: PulseTokens.spaceLg),
                  const ServiceLifecycleControls(compact: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
