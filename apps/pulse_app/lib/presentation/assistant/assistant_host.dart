import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/assistant_controller.dart';

/// Loads Assistant session state once; no floating chrome.
class AssistantHost extends StatefulWidget {
  const AssistantHost({super.key, required this.child});

  final Widget child;

  @override
  State<AssistantHost> createState() => _AssistantHostState();
}

class _AssistantHostState extends State<AssistantHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AssistantController>().load();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
