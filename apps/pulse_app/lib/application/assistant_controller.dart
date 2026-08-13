import 'package:flutter/foundation.dart';

import '../assistant/assistant_models.dart';
import '../assistant/assistant_orchestrator.dart';
import '../assistant/assistant_tools.dart';
import '../assistant/ipc_assistant_tool_layer.dart';
import '../assistant/local_ai_chat.dart';
import '../assistant/local_ai_provider.dart';
import '../assistant/local_ai_types.dart';
import '../assistant/providers/lm_studio_provider.dart';
import '../assistant/providers/ollama_provider.dart';
import '../ipc/pulse_ipc_client.dart';
import 'settings_controller.dart';

/// Session-scoped Pulse Assistant state (local LLM chat + read-only tools).
class AssistantController extends ChangeNotifier {
  AssistantController({
    LocalAiProviderRegistry? registry,
    AssistantToolLayer? tools,
    SettingsController? settings,
    PulseIpcClient? ipc,
    AssistantOrchestrator? orchestrator,
  })  : _settings = settings,
        _registry = registry ??
            LocalAiProviderRegistry(
              providers: [
                OllamaProvider(),
                LmStudioProvider(),
              ],
              preferredProviderId: settings?.assistantLocalAiProviderId,
              preferredModelId: settings?.assistantLocalAiModelId,
            ),
        _tools = tools ??
            (ipc != null
                ? IpcAssistantToolLayer(ipc: ipc)
                : _RejectingToolLayer()) {
    _orchestrator = orchestrator ?? AssistantOrchestrator(tools: _tools);
  }

  final SettingsController? _settings;
  final LocalAiProviderRegistry _registry;
  final AssistantToolLayer _tools;
  late final AssistantOrchestrator _orchestrator;

  bool _panelOpen = false;
  bool _busy = false;
  bool _awaitingReply = false;
  String? _toolActivity;
  LocalAiCancelToken? _activeCancel;
  String? _lastFailedUserText;
  LocalAiDiscoverySnapshot _snapshot = const LocalAiDiscoverySnapshot(
    state: LocalAiConnectionState.checking,
    providerStatuses: {},
  );
  final List<AssistantMessage> _messages = [];
  String _draft = '';
  int _idSeq = 0;

  bool get panelOpen => _panelOpen;
  bool get busy => _busy;
  bool get awaitingReply => _awaitingReply;
  String? get toolActivity => _toolActivity;

  LocalAiDiscoverySnapshot get snapshot => _snapshot;
  LocalAiConnectionState get connectionState => _snapshot.state;
  LocalAiProviderRegistry get registry => _registry;
  AssistantToolLayer get tools => _tools;
  List<AssistantMessage> get messages => List.unmodifiable(_messages);
  String get draft => _draft;

  String get connectionLabel => assistantConnectionLabel(connectionState);

  bool get showLocalPrivacyIndicator => _snapshot.showLocalPrivacyClaim;

  bool get showNotFoundState => switch (connectionState) {
        LocalAiConnectionState.notFound ||
        LocalAiConnectionState.unavailable ||
        LocalAiConnectionState.error =>
          true,
        _ => false,
      };

  bool get showNoModelsState =>
      connectionState == LocalAiConnectionState.noModels;

  bool get showReadyState => connectionState == LocalAiConnectionState.ready;

  bool get showCheckingState =>
      connectionState == LocalAiConnectionState.checking;

  /// Chat composer when a provider+model are ready.
  bool get showChatUi => showReadyState && hasModelSelection;

  bool get canSend =>
      showChatUi &&
      !_awaitingReply &&
      _draft.trim().isNotEmpty &&
      selectedProvider != null &&
      selectedModel != null;

  bool get canCancel => _awaitingReply && _activeCancel != null;

  bool get showSuggestedPrompts =>
      showChatUi && _messages.isEmpty && !_awaitingReply;

  LocalAiProvider? get selectedProvider {
    final id = _snapshot.selectedProviderId;
    if (id == null) return null;
    return _registry.providerById(id);
  }

  List<LocalAiProvider> get reachableProvidersWithModels {
    return _registry.providers.where((p) {
      final s = _snapshot.statusFor(p.id);
      return s?.state == LocalAiConnectionState.ready && s!.hasModels;
    }).toList();
  }

  List<LocalAiModel> get availableModels {
    final id = _snapshot.selectedProviderId;
    if (id == null) return const [];
    return _snapshot.modelsFor(id);
  }

  LocalAiModel? get selectedModel {
    final modelId = _snapshot.selectedModelId;
    if (modelId == null) return null;
    for (final m in availableModels) {
      if (m.id == modelId) return m;
    }
    return null;
  }

  bool get hasModelSelection => selectedModel != null;

  Future<void> load() async {
    _snapshot = const LocalAiDiscoverySnapshot(
      state: LocalAiConnectionState.checking,
      providerStatuses: {},
    );
    notifyListeners();
    _registry.preferredProviderId = _settings?.assistantLocalAiProviderId;
    _registry.preferredModelId = _settings?.assistantLocalAiModelId;
    _snapshot = await _registry.refresh();
    await _persistResolvedSelection();
    notifyListeners();
  }

  void openPanel() {
    if (_panelOpen) return;
    _panelOpen = true;
    notifyListeners();
    unawaitedRefresh();
  }

  void closePanel() {
    if (!_panelOpen) return;
    _panelOpen = false;
    notifyListeners();
  }

  void togglePanel() {
    if (_panelOpen) {
      closePanel();
    } else {
      openPanel();
    }
  }

  void unawaitedRefresh() {
    // ignore: discarded_futures
    refreshConnection();
  }

  Future<void> refreshConnection() async {
    if (_busy || _awaitingReply) return;
    _busy = true;
    _snapshot = const LocalAiDiscoverySnapshot(
      state: LocalAiConnectionState.checking,
      providerStatuses: {},
    );
    notifyListeners();
    try {
      final statuses = <String, LocalAiProviderStatus>{};
      for (final p in _registry.providers) {
        try {
          statuses[p.id] = await p.probe();
        } catch (e) {
          statuses[p.id] = LocalAiProviderStatus.error(
            message: e.toString(),
            detail: '${p.displayName} probe failed',
          );
        }
      }
      _registry.preferredProviderId = _settings?.assistantLocalAiProviderId;
      _registry.preferredModelId = _settings?.assistantLocalAiModelId;
      _snapshot = LocalAiProviderRegistry.resolveSelection(
        providers: _registry.providers,
        statuses: statuses,
        preferredProviderId: _registry.preferredProviderId,
        preferredModelId: _registry.preferredModelId,
      );
      await _persistResolvedSelection();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> selectProvider(String providerId) async {
    final status = _snapshot.statusFor(providerId);
    if (status == null || status.state != LocalAiConnectionState.ready) return;

    _registry.preferredProviderId = providerId;
    final models = status.models;
    // Keep prior model only if it still exists on this provider — never auto-pick.
    String? modelId = _settings?.assistantLocalAiModelId;
    if (modelId == null || !models.any((m) => m.id == modelId)) {
      modelId = null;
    }
    _registry.preferredModelId = modelId;
    _snapshot = LocalAiDiscoverySnapshot(
      state: LocalAiConnectionState.ready,
      providerStatuses: _snapshot.providerStatuses,
      selectedProviderId: providerId,
      selectedModelId: modelId,
      detail: modelId == null ? 'Select a local model' : 'Local AI ready',
    );
    await _settings?.setAssistantLocalAiSelection(
      providerId: providerId,
      modelId: modelId,
    );
    notifyListeners();
  }

  Future<void> selectModel(String modelId) async {
    final providerId = _snapshot.selectedProviderId;
    if (providerId == null) return;
    final models = _snapshot.modelsFor(providerId);
    if (!models.any((m) => m.id == modelId)) return;

    _registry.preferredProviderId = providerId;
    _registry.preferredModelId = modelId;
    _snapshot = LocalAiDiscoverySnapshot(
      state: LocalAiConnectionState.ready,
      providerStatuses: _snapshot.providerStatuses,
      selectedProviderId: providerId,
      selectedModelId: modelId,
      detail: 'Local AI ready',
    );
    await _settings?.setAssistantLocalAiSelection(
      providerId: providerId,
      modelId: modelId,
    );
    notifyListeners();
  }

  void setDraft(String value) {
    if (_draft == value) return;
    _draft = value;
    notifyListeners();
  }

  Future<void> useSuggestedPrompt(String prompt, {bool send = true}) async {
    setDraft(prompt);
    if (send) await sendDraft();
  }

  Future<void> sendDraft() async {
    final text = _draft.trim();
    if (text.isEmpty) return;
    if (!showChatUi ||
        _awaitingReply ||
        selectedProvider == null ||
        selectedModel == null) {
      return;
    }
    _draft = '';
    notifyListeners();
    // Accept the user message immediately; generation continues asynchronously
    // so the composer can clear without waiting for the full reply.
    // ignore: discarded_futures
    _sendUserText(text);
  }

  Future<void> retryLast() async {
    final text = _lastFailedUserText;
    if (text == null || text.isEmpty || _awaitingReply) return;
    // Remove trailing error assistant message if present.
    if (_messages.isNotEmpty && _messages.last.isError) {
      _messages.removeLast();
    }
    await _sendUserText(text);
  }

  void cancelGeneration() {
    _activeCancel?.cancel();
  }

  void clearConversation() {
    cancelGeneration();
    _messages.clear();
    _awaitingReply = false;
    _toolActivity = null;
    _lastFailedUserText = null;
    notifyListeners();
  }

  Future<void> _sendUserText(String text) async {
    final provider = selectedProvider;
    final model = selectedModel;
    if (provider == null || model == null) return;
    if (!showChatUi) return;

    _messages.add(
      AssistantMessage(
        id: _nextId(),
        role: AssistantMessageRole.user,
        text: text,
        createdAt: DateTime.now(),
      ),
    );

    final assistantId = _nextId();
    _messages.add(
      AssistantMessage(
        id: assistantId,
        role: AssistantMessageRole.assistant,
        text: '',
        createdAt: DateTime.now(),
        isStreaming: true,
      ),
    );

    final history = _historyForProvider(excludeTrailingAssistantId: assistantId);
    final cancel = LocalAiCancelToken();
    _activeCancel = cancel;
    _awaitingReply = true;
    _toolActivity = null;
    _lastFailedUserText = text;
    notifyListeners();

    void patchAssistant(AssistantMessage Function(AssistantMessage) fn) {
      final i = _messages.indexWhere((m) => m.id == assistantId);
      if (i < 0) return;
      _messages[i] = fn(_messages[i]);
      notifyListeners();
    }

    try {
      final result = await _orchestrator.runTurn(
        provider: provider,
        modelId: model.id,
        history: history,
        userMessage: text,
        cancelToken: cancel,
        stream: true,
        onTextDelta: (delta) {
          patchAssistant(
            (m) => m.copyWith(
              text: m.text + delta,
              clearToolActivity: true,
            ),
          );
        },
        onToolActivity: (label) {
          _toolActivity = label;
          patchAssistant((m) => m.copyWith(toolActivity: label));
        },
      );

      if (result.cancelled) {
        patchAssistant(
          (m) => m.copyWith(
            text: m.text.trim().isEmpty ? 'Cancelled.' : m.text,
            isStreaming: false,
            clearToolActivity: true,
            toolsConsulted: result.toolsUsed,
          ),
        );
        return;
      }

      if (!result.ok) {
        patchAssistant(
          (m) => m.copyWith(
            text: result.errorMessage ?? 'Something went wrong.',
            isStreaming: false,
            isError: true,
            canRetry: true,
            clearToolActivity: true,
            toolsConsulted: result.toolsUsed,
            errorCode: result.errorCode,
          ),
        );
        return;
      }

      _lastFailedUserText = null;
      patchAssistant(
        (m) => m.copyWith(
          text: result.text,
          isStreaming: false,
          clearToolActivity: true,
          toolsConsulted: result.toolsUsed,
        ),
      );
    } finally {
      _awaitingReply = false;
      _toolActivity = null;
      _activeCancel = null;
      notifyListeners();
    }
  }

  List<LocalAiChatMessage> _historyForProvider({
    required String excludeTrailingAssistantId,
  }) {
    final out = <LocalAiChatMessage>[];
    for (final m in _messages) {
      if (m.id == excludeTrailingAssistantId) continue;
      if (m.isError) continue;
      if (m.role == AssistantMessageRole.user) {
        out.add(LocalAiChatMessage.user(m.text));
      } else if (m.role == AssistantMessageRole.assistant &&
          m.text.trim().isNotEmpty) {
        out.add(LocalAiChatMessage.assistant(m.text));
      }
    }
    // Drop the user message we just appended — orchestrator adds it.
    if (out.isNotEmpty && out.last.role == LocalAiMessageRole.user) {
      out.removeLast();
    }
    return out;
  }

  String _nextId() => 'm${++_idSeq}';

  Future<void> _persistResolvedSelection() async {
    final settings = _settings;
    if (settings == null) return;
    final providerId = _snapshot.selectedProviderId;
    final modelId = _snapshot.selectedModelId;
    if (providerId == settings.assistantLocalAiProviderId &&
        modelId == settings.assistantLocalAiModelId) {
      return;
    }
    // Persist restores and clears (e.g. preferred model no longer available).
    // Never invent a new selection here — resolveSelection is manual-only.
    final hadPersisted = settings.assistantLocalAiProviderId != null ||
        settings.assistantLocalAiModelId != null;
    if (providerId == null && modelId == null && !hadPersisted) return;
    await settings.setAssistantLocalAiSelection(
      providerId: providerId,
      modelId: modelId,
    );
  }
}

class _RejectingToolLayer implements AssistantToolLayer {
  @override
  List<AssistantToolDescriptor> listTools() =>
      List.unmodifiable(const []);

  @override
  Future<AssistantToolResult> invoke(
    String toolName, {
    Map<String, Object?> arguments = const {},
  }) async {
    return const AssistantToolResult(
      ok: false,
      errorCode: 'PULSE_SERVICE_UNAVAILABLE',
      errorMessage: 'PulseService is unavailable.',
    );
  }
}
