import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../app/theme/pulse_theme.dart';
import '../../application/assistant_controller.dart';
import '../../application/shell_navigation.dart';
import '../../assistant/assistant_models.dart';
import '../../assistant/local_ai_types.dart';
import '../components/pulse_button.dart';
import '../components/pulse_section_header.dart';
import '../design_system/pulse_dialog.dart';

/// In-page Assistant workspace (sidebar destination content).
class AssistantView extends StatelessWidget {
  const AssistantView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AssistantHeader(),
        SoftDivider(),
        Expanded(child: _AssistantBody()),
      ],
    );
  }
}

class _AssistantHeader extends StatelessWidget {
  const _AssistantHeader();

  @override
  Widget build(BuildContext context) {
    final connection = context.select<AssistantController, String>(
      (c) => c.connectionLabel,
    );
    final availability =
        context.select<AssistantController, LocalAiConnectionState>(
      (c) => c.connectionState,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: PulseTokens.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
              border: Border.all(color: PulseTokens.border),
            ),
            child: Icon(
              LucideIcons.bot,
              size: 18,
              color: PulseTokens.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local AI diagnostics chat',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _StatusDot(availability: availability),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        connection,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PulseTokens.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.availability});

  final LocalAiConnectionState availability;

  @override
  Widget build(BuildContext context) {
    final color = switch (availability) {
      LocalAiConnectionState.ready ||
      LocalAiConnectionState.noModels ||
      LocalAiConnectionState.runtimeAvailable =>
        PulseTokens.success,
      LocalAiConnectionState.checking => PulseTokens.warning,
      _ => PulseTokens.textTertiary,
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _AssistantBody extends StatelessWidget {
  const _AssistantBody();

  @override
  Widget build(BuildContext context) {
    final checking = context.select<AssistantController, bool>(
      (c) => c.showCheckingState,
    );
    final notFound = context.select<AssistantController, bool>(
      (c) => c.showNotFoundState,
    );
    final noModels = context.select<AssistantController, bool>(
      (c) => c.showNoModelsState,
    );
    final ready = context.select<AssistantController, bool>(
      (c) => c.showReadyState,
    );

    if (checking) return const _CheckingState();
    if (ready) return const _ReadyRuntimeState();
    if (noModels) return const _NoModelsState();
    if (notFound) return const _EmptyLocalAiState();
    return const _EmptyLocalAiState();
  }
}

class _CheckingState extends StatelessWidget {
  const _CheckingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PulseTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PulseTokens.accent,
              ),
            ),
            const SizedBox(height: PulseTokens.spaceMd),
            Text(
              'Checking local AI...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: PulseTokens.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLocalAiState extends StatelessWidget {
  const _EmptyLocalAiState();

  static const _learnMessage =
      'Pulse Assistant talks to a local AI runtime that you install and manage yourself '
      '(for example Ollama or LM Studio).\n\n'
      'Pulse never downloads AI models, never runs third-party installers, and never '
      'modifies your system to set up AI software.\n\n'
      'After a supported runtime is available on this PC, return here to connect it. '
      'You can also use Pulse diagnostics today through local MCP integrations in '
      'Cursor, Claude Desktop, Windsurf, Cline, or VS Code.';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: PulseTokens.accentSoft,
                        borderRadius:
                            BorderRadius.circular(PulseTokens.radiusXl),
                        border: Border.all(
                          color: PulseTokens.accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        LucideIcons.bot,
                        size: 26,
                        color: PulseTokens.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: PulseTokens.spaceMd),
                  Text(
                    'Local AI not found',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: PulseTokens.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Pulse Assistant uses a local AI model to analyze your system without sending your diagnostic data to a cloud service.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: PulseTokens.textSecondary,
                          height: 1.5,
                          fontSize: 13.5,
                        ),
                  ),
                  const SizedBox(height: PulseTokens.spaceLg),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: PulseTokens.card,
                      borderRadius:
                          BorderRadius.circular(PulseTokens.radiusMd),
                      border: Border.all(color: PulseTokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Use a local AI runtime',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Install a supported local AI runtime such as Ollama or LM Studio, then return to Pulse to connect your model.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: PulseTokens.textSecondary,
                                    height: 1.45,
                                    fontSize: 13,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Supported runtimes',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: PulseTokens.textTertiary,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        const Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _RuntimeChip(label: 'Ollama'),
                            _RuntimeChip(label: 'LM Studio'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () {
                showPulseDialog(
                  context: context,
                  title: 'Local AI runtimes',
                  message: _learnMessage,
                  confirmLabel: 'Got it',
                );
              },
              child: Text(
                'Learn about local AI',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: PulseTokens.accent,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _FullWidthAction(
            label: 'Explore MCP integrations',
            icon: LucideIcons.bot,
            primary: false,
            onPressed: () {
              final nav = context.read<ShellNavigation>();
              nav.openAiIntegrationSettings();
            },
          ),
        ],
      ),
    );
  }
}

class _NoModelsState extends StatelessWidget {
  const _NoModelsState();

  @override
  Widget build(BuildContext context) {
    final providerName = context.select<AssistantController, String>((c) {
      final selected = c.selectedProvider?.displayName;
      if (selected != null) return selected;
      for (final p in c.registry.providers) {
        final s = c.snapshot.statusFor(p.id);
        if (s?.state == LocalAiConnectionState.noModels) {
          return p.displayName;
        }
      }
      return 'Local AI';
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (context
                      .watch<AssistantController>()
                      .showLocalPrivacyIndicator)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: _InlinePrivacyNote(),
                    ),
                  Text(
                    'Local AI connected',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    providerName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PulseTokens.textTertiary,
                        ),
                  ),
                  const SizedBox(height: PulseTokens.spaceMd),
                  Text(
                    'No local models found',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your local AI runtime is reachable, but Pulse did not find any models. '
                    'Download or install a model in Ollama or LM Studio yourself, then return here. '
                    'Pulse never downloads or installs AI models.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: PulseTokens.textSecondary,
                          height: 1.5,
                          fontSize: 13.5,
                        ),
                  ),
                ],
              ),
            ),
          ),
          PulseButton(
            label: 'Refresh',
            icon: LucideIcons.refreshCw,
            variant: PulseButtonVariant.secondary,
            expanded: true,
            onPressed: () =>
                context.read<AssistantController>().refreshConnection(),
          ),
          const SizedBox(height: 10),
          _FullWidthAction(
            label: 'Explore MCP integrations',
            icon: LucideIcons.bot,
            primary: false,
            onPressed: () {
              final nav = context.read<ShellNavigation>();
              nav.openAiIntegrationSettings();
            },
          ),
        ],
      ),
    );
  }
}

class _ReadyRuntimeState extends StatelessWidget {
  const _ReadyRuntimeState();

  @override
  Widget build(BuildContext context) {
    final showChat = context.select<AssistantController, bool>((c) => c.showChatUi);
    if (showChat) return const _ChatReadyState();
    return const _ModelPickerState();
  }
}

class _ModelPickerState extends StatelessWidget {
  const _ModelPickerState();

  @override
  Widget build(BuildContext context) {
    final assistant = context.watch<AssistantController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (assistant.showLocalPrivacyIndicator) const _PrivacyStrip(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              Text(
                'Local AI connected',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Select a local runtime and model to start chatting. '
                'Pulse Assistant uses read-only diagnostics only.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PulseTokens.textSecondary,
                      height: 1.45,
                      fontSize: 13,
                    ),
              ),
              const SizedBox(height: PulseTokens.spaceMd),
              const _LocalAiSelectionControls(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: PulseButton(
            label: 'Refresh',
            icon: LucideIcons.refreshCw,
            variant: PulseButtonVariant.secondary,
            expanded: true,
            onPressed: assistant.busy
                ? null
                : () => assistant.refreshConnection(),
          ),
        ),
      ],
    );
  }
}

/// Provider + model dropdowns — always available so the user can change
/// a previously persisted selection.
class _LocalAiSelectionControls extends StatelessWidget {
  const _LocalAiSelectionControls({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final assistant = context.watch<AssistantController>();
    final providers = assistant.reachableProvidersWithModels;
    final selectedProvider = assistant.selectedProvider;
    final models = assistant.availableModels;
    final selectedModel = assistant.selectedModel;
    final enabled = !assistant.awaitingReply;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Provider',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: PulseTokens.textTertiary,
              ),
        ),
        SizedBox(height: compact ? 4 : 6),
        if (providers.isEmpty)
          Text(
            'No provider selected',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          InputDecorator(
            decoration: _fieldDecoration(compact: compact),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedProvider?.id,
                isExpanded: true,
                isDense: compact,
                hint: const Text('Select provider'),
                items: [
                  for (final p in providers)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.displayName),
                    ),
                ],
                onChanged: !enabled
                    ? null
                    : (id) {
                        if (id != null) {
                          context.read<AssistantController>().selectProvider(id);
                        }
                      },
              ),
            ),
          ),
        SizedBox(height: compact ? PulseTokens.spaceSm : PulseTokens.spaceMd),
        Text(
          'Model',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: PulseTokens.textTertiary,
              ),
        ),
        SizedBox(height: compact ? 4 : 6),
        if (selectedProvider == null)
          Text(
            providers.isEmpty ? 'Waiting for provider' : 'Select a provider',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PulseTokens.textSecondary,
                ),
          )
        else if (models.isEmpty)
          Text(
            'No models',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          InputDecorator(
            decoration: _fieldDecoration(compact: compact),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedModel?.id,
                isExpanded: true,
                isDense: compact,
                hint: const Text('Select a model'),
                items: [
                  for (final m in models)
                    DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        m.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: !enabled
                    ? null
                    : (id) {
                        if (id != null) {
                          context.read<AssistantController>().selectModel(id);
                        }
                      },
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatReadyState extends StatefulWidget {
  const _ChatReadyState();

  @override
  State<_ChatReadyState> createState() => _ChatReadyStateState();
}

class _ChatReadyStateState extends State<_ChatReadyState> {
  final _scroll = ScrollController();
  final _composer = TextEditingController();

  @override
  void dispose() {
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _submit() async {
    final assistant = context.read<AssistantController>();
    final text = _composer.text.trim();
    if (text.isEmpty || !assistant.canSend) return;
    assistant.setDraft(text);
    await assistant.sendDraft();
    if (!mounted) return;
    // Clear only after submission accepted (draft emptied by controller).
    if (assistant.draft.isEmpty) {
      _composer.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final assistant = context.watch<AssistantController>();
    final messages = assistant.messages;
    final activity = assistant.toolActivity;
    final modelLabel = assistant.selectedModel?.displayName ?? 'model';
    final providerLabel = assistant.selectedProvider?.displayName ?? 'Local AI';

    if (messages.isNotEmpty || assistant.awaitingReply) {
      _scrollToLatest();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (assistant.showLocalPrivacyIndicator) const _PrivacyStrip(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$providerLabel · $modelLabel',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: PulseTokens.textTertiary,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: assistant.awaitingReply
                        ? null
                        : () => assistant.clearConversation(),
                    child: const Text('Clear chat'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const _LocalAiSelectionControls(compact: true),
            ],
          ),
        ),
        Expanded(
          child: messages.isEmpty && !assistant.awaitingReply
              ? _EmptyChatHints(
                  onPrompt: (p) async {
                    _composer.text = p;
                    assistant.setDraft(p);
                    await _submit();
                  },
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _ChatBubble(message: messages[index]);
                  },
                ),
        ),
        if (activity != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: PulseTokens.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activity,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PulseTokens.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        SoftDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  enabled: !assistant.awaitingReply,
                  minLines: 1,
                  maxLines: 4,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Ask about this PC…',
                    filled: true,
                    fillColor: PulseTokens.card,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
                      borderSide: BorderSide(color: PulseTokens.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
                      borderSide: BorderSide(color: PulseTokens.border),
                    ),
                  ),
                  onChanged: assistant.setDraft,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              if (assistant.canCancel)
                IconButton.filled(
                  tooltip: 'Cancel',
                  onPressed: assistant.cancelGeneration,
                  style: IconButton.styleFrom(
                    backgroundColor: PulseTokens.card,
                    foregroundColor: PulseTokens.textPrimary,
                  ),
                  icon: const Icon(LucideIcons.square, size: 16),
                )
              else
                IconButton.filled(
                  tooltip: 'Send',
                  onPressed: assistant.canSend ? _submit : null,
                  style: IconButton.styleFrom(
                    backgroundColor: PulseTokens.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        PulseTokens.accent.withValues(alpha: 0.35),
                  ),
                  icon: const Icon(LucideIcons.send, size: 16),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyChatHints extends StatelessWidget {
  const _EmptyChatHints({required this.onPrompt});

  final void Function(String prompt) onPrompt;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        Text(
          'Ask about this Windows PC',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pulse Assistant can inspect read-only diagnostics through your local model.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: PulseTokens.textSecondary,
                height: 1.4,
                fontSize: 13,
              ),
        ),
        const SizedBox(height: PulseTokens.spaceMd),
        for (final prompt in AssistantSuggestedPrompts.values) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => onPrompt(prompt),
            borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
                border: Border.all(color: PulseTokens.border),
                color: PulseTokens.card,
              ),
              child: Text(
                prompt,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                    ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AssistantMessageRole.user;
    final align =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isUser ? PulseTokens.accentSoft : PulseTokens.card;
    final fg = message.isError
        ? PulseTokens.error
        : PulseTokens.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
              border: Border.all(
                color: message.isError
                    ? PulseTokens.error.withValues(alpha: 0.35)
                    : PulseTokens.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.toolActivity != null && message.isStreaming) ...[
                  Text(
                    message.toolActivity!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PulseTokens.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (message.text.isNotEmpty)
                  Text(
                    message.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: fg,
                          height: 1.4,
                          fontSize: 13.5,
                        ),
                  )
                else if (message.isStreaming)
                  Text(
                    'Thinking…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PulseTokens.textSecondary,
                        ),
                  ),
                if (message.toolsConsulted.isNotEmpty &&
                    !message.isStreaming) ...[
                  const SizedBox(height: 8),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Analyzed',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: PulseTokens.textTertiary,
                            ),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            message.toolsConsulted
                                .map(assistantToolConsultedLabel)
                                .join(' · '),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: PulseTokens.textSecondary,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (message.isError && message.canRetry)
            TextButton(
              onPressed: () => context.read<AssistantController>().retryLast(),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration({bool compact = false}) {
  return InputDecoration(
    filled: true,
    fillColor: PulseTokens.card,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: compact ? 6 : 10,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
      borderSide: BorderSide(color: PulseTokens.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
      borderSide: BorderSide(color: PulseTokens.border),
    ),
  );
}


class _InlinePrivacyNote extends StatelessWidget {
  const _InlinePrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(LucideIcons.shieldCheck, size: 14, color: PulseTokens.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Local AI · Your diagnostic data stays on this PC',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PulseTokens.success,
                  fontSize: 11.5,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}

class _RuntimeChip extends StatelessWidget {
  const _RuntimeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PulseTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(PulseTokens.radiusSm),
        border: Border.all(color: PulseTokens.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: PulseTokens.textSecondary,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

class _FullWidthAction extends StatelessWidget {
  const _FullWidthAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? PulseTokens.accent : PulseTokens.card;
    final fg = primary ? Colors.white : PulseTokens.textPrimary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PulseTokens.radiusMd),
            border: primary
                ? null
                : Border.all(color: PulseTokens.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyStrip extends StatelessWidget {
  const _PrivacyStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: PulseTokens.successSoft.withValues(alpha: 0.45),
      child: Row(
        children: [
          Icon(LucideIcons.shieldCheck, size: 14, color: PulseTokens.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Local AI · Your diagnostic data stays on this PC',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PulseTokens.success,
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
