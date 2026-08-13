import 'local_ai_types.dart';

enum AssistantMessageRole { user, assistant, system }

/// In-session chat message (not persisted across app restarts).
class AssistantMessage {
  const AssistantMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.isStreaming = false,
    this.isError = false,
    this.canRetry = false,
    this.toolActivity,
    this.toolsConsulted = const [],
    this.errorCode,
  });

  final String id;
  final AssistantMessageRole role;
  final String text;
  final DateTime createdAt;
  final bool isStreaming;
  final bool isError;
  final bool canRetry;
  final String? toolActivity;
  final List<String> toolsConsulted;
  final String? errorCode;

  AssistantMessage copyWith({
    String? text,
    bool? isStreaming,
    bool? isError,
    bool? canRetry,
    String? toolActivity,
    List<String>? toolsConsulted,
    String? errorCode,
    bool clearToolActivity = false,
  }) {
    return AssistantMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      createdAt: createdAt,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
      canRetry: canRetry ?? this.canRetry,
      toolActivity:
          clearToolActivity ? null : (toolActivity ?? this.toolActivity),
      toolsConsulted: toolsConsulted ?? this.toolsConsulted,
      errorCode: errorCode ?? this.errorCode,
    );
  }
}

/// Suggested starter prompts when chat is ready.
abstract final class AssistantSuggestedPrompts {
  static const values = <String>[
    'Why is my PC slow?',
    'Analyze my system health',
    "What's using the most memory?",
    'Are there any critical issues?',
  ];
}

/// Human-readable connection line under the panel title.
String assistantConnectionLabel(LocalAiConnectionState state) {
  return switch (state) {
    LocalAiConnectionState.checking => 'Checking local AI...',
    LocalAiConnectionState.ready ||
    LocalAiConnectionState.noModels ||
    LocalAiConnectionState.runtimeAvailable =>
      'Local AI connected',
    LocalAiConnectionState.notFound ||
    LocalAiConnectionState.unavailable ||
    LocalAiConnectionState.error =>
      'Local AI not found',
  };
}

String assistantToolConsultedLabel(String toolName) {
  return switch (toolName) {
    'mcp_self' => 'Assistant status',
    'system_health' => 'System health',
    'system_cpu' => 'CPU',
    'system_memory' => 'Memory',
    'system_gpu' => 'GPU',
    'system_storage' => 'Storage',
    'system_network' => 'Network',
    'process_list' => 'Processes',
    'process_search' => 'Process search',
    'process_details' => 'Process details',
    'timeline_list' => 'Timeline',
    'timeline_search' => 'Timeline search',
    'diagnostics_snapshot' => 'Diagnostics',
    'service_status' => 'PulseService',
    _ => toolName,
  };
}
