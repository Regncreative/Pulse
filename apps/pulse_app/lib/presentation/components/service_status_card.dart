import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/pulse_theme.dart';
import '../../ipc/pulse_ipc_client.dart';
import 'connection_indicator.dart';

/// Compact sidebar card summarizing PulseService connection health.
class ServiceStatusCard extends StatelessWidget {
  const ServiceStatusCard({
    super.key,
    required this.state,
    required this.serviceVersion,
  });

  final IpcConnectionState state;
  final String serviceVersion;

  bool get _connected => state == IpcConnectionState.connected;
  bool get _listening =>
      state == IpcConnectionState.connected ||
      state == IpcConnectionState.connecting;

  String get _statusTitle => switch (state) {
        IpcConnectionState.connected => 'Live Monitoring',
        IpcConnectionState.connecting => 'Connecting',
        IpcConnectionState.error => 'Offline',
        IpcConnectionState.disconnected => 'Offline',
      };

  Color get _statusColor => switch (state) {
        IpcConnectionState.connected => PulseTokens.success,
        IpcConnectionState.connecting => PulseTokens.severityWarning,
        IpcConnectionState.error => PulseTokens.error,
        IpcConnectionState.disconnected => PulseTokens.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    final version = serviceVersion.isEmpty ? '—' : serviceVersion;

    return AnimatedContainer(
      duration: PulseTokens.motionNormal,
      curve: PulseTokens.motionCurve,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PulseTokens.acrylicFill,
        borderRadius: BorderRadius.circular(PulseTokens.radiusCard),
        border: Border.all(
          color: _connected
              ? PulseTokens.success.withValues(alpha: 0.28)
              : PulseTokens.strokeSubtle,
        ),
        boxShadow: PulseTokens.elevationSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ConnectionDot(state: state, size: 9),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: PulseTokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _connected ? 'Live' : 'Idle',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: LucideIcons.radio,
            label: 'Listening',
            value: _listening ? 'Yes' : 'No',
            valueColor: _listening ? PulseTokens.success : PulseTokens.textTertiary,
          ),
          const SizedBox(height: 8),
          _StatusRow(
            icon: LucideIcons.package,
            label: 'Version',
            value: version,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: PulseTokens.textTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.textTertiary,
                ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: valueColor ?? PulseTokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}
