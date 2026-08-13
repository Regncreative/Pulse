/// Cancellation token for local LLM chat / tool-loop turns.
class LocalAiCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const LocalAiCancelledException();
    }
  }
}

class LocalAiCancelledException implements Exception {
  const LocalAiCancelledException();

  @override
  String toString() => 'Local AI request cancelled';
}

class LocalAiChatException implements Exception {
  const LocalAiChatException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Provider-agnostic chat request (no Ollama/LM Studio JSON leakage).
class LocalAiChatRequest {
  const LocalAiChatRequest({
    required this.modelId,
    required this.messages,
    this.tools = const [],
    this.stream = false,
    this.cancelToken,
    this.onTextDelta,
    this.timeout = const Duration(seconds: 120),
  });

  final String modelId;
  final List<LocalAiChatMessage> messages;
  final List<LocalAiToolDefinition> tools;
  final bool stream;
  final LocalAiCancelToken? cancelToken;
  final void Function(String delta)? onTextDelta;
  final Duration timeout;
}

/// One model turn: either assistant text and/or tool call requests.
class LocalAiChatTurn {
  const LocalAiChatTurn({
    this.content,
    this.toolCalls = const [],
    this.finishReason,
  });

  final String? content;
  final List<LocalAiToolCall> toolCalls;
  final String? finishReason;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Chat message roles shared across local providers.
enum LocalAiMessageRole { system, user, assistant, tool }

class LocalAiChatMessage {
  const LocalAiChatMessage({
    required this.role,
    this.content,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });

  final LocalAiMessageRole role;
  final String? content;
  final List<LocalAiToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;

  factory LocalAiChatMessage.system(String content) =>
      LocalAiChatMessage(role: LocalAiMessageRole.system, content: content);

  factory LocalAiChatMessage.user(String content) =>
      LocalAiChatMessage(role: LocalAiMessageRole.user, content: content);

  factory LocalAiChatMessage.assistant(
    String? content, {
    List<LocalAiToolCall> toolCalls = const [],
  }) =>
      LocalAiChatMessage(
        role: LocalAiMessageRole.assistant,
        content: content,
        toolCalls: toolCalls,
      );

  factory LocalAiChatMessage.toolResult({
    required String toolCallId,
    required String toolName,
    required String content,
  }) =>
      LocalAiChatMessage(
        role: LocalAiMessageRole.tool,
        content: content,
        toolCallId: toolCallId,
        toolName: toolName,
      );
}

class LocalAiToolDefinition {
  const LocalAiToolDefinition({
    required this.name,
    required this.description,
    this.parameters = const {'type': 'object', 'properties': <String, Object?>{}},
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

class LocalAiToolCall {
  const LocalAiToolCall({
    required this.id,
    required this.name,
    this.arguments = const {},
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;
}
