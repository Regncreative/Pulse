/// Connection states for local AI runtime detection (Assistant Phase 2).
enum LocalAiConnectionState {
  /// Probe in progress.
  checking,

  /// No local runtime reachable on localhost.
  notFound,

  /// Runtime process/API is present (transitional; prefer [noModels]/[ready]).
  runtimeAvailable,

  /// Runtime reachable but no selectable models.
  noModels,

  /// Runtime reachable with at least one model (selection may still be needed).
  ready,

  /// Runtime known but API unreachable / disabled.
  unavailable,

  /// Probe failed (timeout, malformed payload, unexpected HTTP).
  error,
}

/// A model discovered from a local runtime (Ollama / LM Studio).
class LocalAiModel {
  const LocalAiModel({
    required this.id,
    required this.displayName,
    this.metadata = const {},
  });

  /// Stable identifier used when talking to the runtime API.
  final String id;

  /// Human-readable label for Settings / Assistant UI.
  final String displayName;

  /// Optional provider-specific metadata (size, family, quantization, …).
  final Map<String, Object?> metadata;

  @override
  bool operator ==(Object other) =>
      other is LocalAiModel && other.id == id && other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, displayName);
}

/// Result of probing a single [LocalAiProvider].
class LocalAiProviderStatus {
  const LocalAiProviderStatus({
    required this.state,
    this.models = const [],
    this.detail,
    this.errorMessage,
  });

  final LocalAiConnectionState state;
  final List<LocalAiModel> models;
  final String? detail;
  final String? errorMessage;

  bool get hasModels => models.isNotEmpty;

  factory LocalAiProviderStatus.notFound({String? detail}) =>
      LocalAiProviderStatus(
        state: LocalAiConnectionState.notFound,
        detail: detail ?? 'Local AI runtime not found',
      );

  factory LocalAiProviderStatus.noModels({String? detail}) =>
      LocalAiProviderStatus(
        state: LocalAiConnectionState.noModels,
        detail: detail ?? 'No local models found',
      );

  factory LocalAiProviderStatus.ready({
    required List<LocalAiModel> models,
    String? detail,
  }) =>
      LocalAiProviderStatus(
        state: LocalAiConnectionState.ready,
        models: List.unmodifiable(models),
        detail: detail,
      );

  factory LocalAiProviderStatus.unavailable({String? detail}) =>
      LocalAiProviderStatus(
        state: LocalAiConnectionState.unavailable,
        detail: detail ?? 'Local AI runtime unavailable',
      );

  factory LocalAiProviderStatus.error({
    required String message,
    String? detail,
  }) =>
      LocalAiProviderStatus(
        state: LocalAiConnectionState.error,
        detail: detail ?? message,
        errorMessage: message,
      );
}
