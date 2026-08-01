import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../application/connection_controller.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import '../components/pulse_empty_state.dart';

/// Stub reports surface — Phase E fills branded export workflows.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: title,
          connectionState: state,
          connectionLabel: connectionLabel,
        ),
        const Expanded(
          child: PulseEmptyState(
            icon: LucideIcons.fileText,
            title: 'Reports',
            message:
                'Export System Health, Timeline, and Diagnostics as branded reports.',
          ),
        ),
      ],
    );
  }
}
