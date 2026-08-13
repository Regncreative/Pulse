import 'local_ai_chat.dart';
import 'local_ai_types.dart';

/// Local LLM host adapter (localhost only).
///
/// Implementations: OllamaProvider, LmStudioProvider.
abstract class LocalAiProvider {
  String get id;
  String get displayName;

  /// Always true for on-device hosts. Cloud providers are out of scope.
  bool get isLocal;

  /// Loopback base URI (scheme + host + port). Must be localhost.
  Uri get baseUri;

  Future<LocalAiProviderStatus> probe();

  /// Chat completion with optional tool definitions / tool results.
  ///
  /// Provider-specific wire JSON stays inside Ollama / LM Studio adapters.
  Future<LocalAiChatTurn> chat(LocalAiChatRequest request);
}

/// Snapshot after probing every registered provider.
class LocalAiDiscoverySnapshot {
  const LocalAiDiscoverySnapshot({
    required this.state,
    required this.providerStatuses,
    this.selectedProviderId,
    this.selectedModelId,
    this.detail,
  });

  final LocalAiConnectionState state;
  final Map<String, LocalAiProviderStatus> providerStatuses;
  final String? selectedProviderId;
  final String? selectedModelId;
  final String? detail;

  LocalAiProviderStatus? statusFor(String providerId) =>
      providerStatuses[providerId];

  List<LocalAiModel> modelsFor(String providerId) =>
      providerStatuses[providerId]?.models ?? const [];

  bool get showLocalPrivacyClaim =>
      state == LocalAiConnectionState.ready ||
      state == LocalAiConnectionState.noModels;

  static const empty = LocalAiDiscoverySnapshot(
    state: LocalAiConnectionState.notFound,
    providerStatuses: {},
    detail: 'No local AI provider registered',
  );
}

/// Discovers Ollama / LM Studio and resolves preferred selection.
class LocalAiProviderRegistry {
  LocalAiProviderRegistry({
    List<LocalAiProvider>? providers,
    this.preferredProviderId,
    this.preferredModelId,
  }) : _providers = List.unmodifiable(providers ?? const []);

  final List<LocalAiProvider> _providers;
  String? preferredProviderId;
  String? preferredModelId;

  LocalAiDiscoverySnapshot _last = LocalAiDiscoverySnapshot.empty;

  List<LocalAiProvider> get providers => _providers;
  LocalAiDiscoverySnapshot get lastSnapshot => _last;

  LocalAiProvider? providerById(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<LocalAiDiscoverySnapshot> refresh() async {
    if (_providers.isEmpty) {
      _last = LocalAiDiscoverySnapshot.empty;
      return _last;
    }

    final statuses = <String, LocalAiProviderStatus>{};
    for (final p in _providers) {
      try {
        statuses[p.id] = await p.probe();
      } catch (e) {
        statuses[p.id] = LocalAiProviderStatus.error(
          message: e.toString(),
          detail: '${p.displayName} probe failed',
        );
      }
    }

    // Re-read preferences after awaits so concurrent UI selection wins.
    _last = resolveSelection(
      providers: _providers,
      statuses: statuses,
      preferredProviderId: preferredProviderId,
      preferredModelId: preferredModelId,
    );
    return _last;
  }

  /// Pure selection + aggregate state (unit-tested).
  static LocalAiDiscoverySnapshot resolveSelection({
    required List<LocalAiProvider> providers,
    required Map<String, LocalAiProviderStatus> statuses,
    String? preferredProviderId,
    String? preferredModelId,
  }) {
    final readyIds = <String>[];
    final noModelIds = <String>[];
    var sawUnavailable = false;
    var sawError = false;

    for (final p in providers) {
      final s = statuses[p.id];
      if (s == null) continue;
      switch (s.state) {
        case LocalAiConnectionState.ready:
          readyIds.add(p.id);
        case LocalAiConnectionState.noModels:
        case LocalAiConnectionState.runtimeAvailable:
          noModelIds.add(p.id);
        case LocalAiConnectionState.unavailable:
          sawUnavailable = true;
        case LocalAiConnectionState.error:
          sawError = true;
        case LocalAiConnectionState.notFound:
        case LocalAiConnectionState.checking:
          break;
      }
    }

    if (readyIds.isEmpty && noModelIds.isEmpty) {
      final state = sawError
          ? LocalAiConnectionState.error
          : (sawUnavailable
              ? LocalAiConnectionState.unavailable
              : LocalAiConnectionState.notFound);
      return LocalAiDiscoverySnapshot(
        state: state,
        providerStatuses: Map.unmodifiable(statuses),
        detail: state == LocalAiConnectionState.notFound
            ? 'No local AI detected'
            : 'Local AI runtime unavailable',
      );
    }

    if (readyIds.isEmpty) {
      final providerId = _pickProviderId(
        candidates: noModelIds,
        preferredProviderId: preferredProviderId,
      );
      return LocalAiDiscoverySnapshot(
        state: LocalAiConnectionState.noModels,
        providerStatuses: Map.unmodifiable(statuses),
        selectedProviderId: providerId,
        selectedModelId: null,
        detail: 'No local models found',
      );
    }

    final providerId = _pickProviderId(
      candidates: readyIds,
      preferredProviderId: preferredProviderId,
    );
    if (providerId == null) {
      return LocalAiDiscoverySnapshot(
        state: LocalAiConnectionState.ready,
        providerStatuses: Map.unmodifiable(statuses),
        selectedProviderId: null,
        selectedModelId: null,
        detail: 'Select a local AI runtime',
      );
    }

    final models = statuses[providerId]?.models ?? const <LocalAiModel>[];
    final modelId = _pickModelId(
      models: models,
      preferredModelId: preferredModelId,
      autoSelectSingle: false,
    );

    return LocalAiDiscoverySnapshot(
      state: LocalAiConnectionState.ready,
      providerStatuses: Map.unmodifiable(statuses),
      selectedProviderId: providerId,
      selectedModelId: modelId,
      detail: modelId == null ? 'Select a local model' : 'Local AI ready',
    );
  }

  static String? _pickProviderId({
    required List<String> candidates,
    String? preferredProviderId,
  }) {
    if (candidates.isEmpty) return null;
    // Only restore an explicit prior selection — never auto-pick.
    if (preferredProviderId != null &&
        candidates.contains(preferredProviderId)) {
      return preferredProviderId;
    }
    return null;
  }

  static String? _pickModelId({
    required List<LocalAiModel> models,
    String? preferredModelId,
    required bool autoSelectSingle,
  }) {
    if (models.isEmpty) return null;
    // Only restore an explicit prior selection — never auto-pick.
    if (preferredModelId != null &&
        models.any((m) => m.id == preferredModelId)) {
      return preferredModelId;
    }
    if (autoSelectSingle && models.length == 1) return models.first.id;
    return null;
  }
}
