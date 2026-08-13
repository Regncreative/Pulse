import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/assistant_controller.dart';
import '../../application/connection_controller.dart';
import '../../ipc/pulse_ipc_client.dart';
import '../components/pulse_app_bar.dart';
import 'assistant_panel.dart';

/// Full-page Pulse Assistant (sidebar destination — not a floating widget).
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.title});

  final String title;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AssistantController>().unawaitedRefresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.select<PulseIpcClient, IpcConnectionState>(
      (c) => c.status.state,
    );
    final connectionLabel = context.select<ConnectionController, String>(
      (c) => c.statusLabel,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PulseAppBar(
          title: widget.title,
          connectionState: state,
          connectionLabel: connectionLabel,
        ),
        const Expanded(child: AssistantView()),
      ],
    );
  }
}
