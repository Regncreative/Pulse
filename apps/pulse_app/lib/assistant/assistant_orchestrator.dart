import 'assistant_system_prompt.dart';
import 'assistant_tools.dart';
import 'diagnostic_tool_allowlist.dart';
import 'ipc_assistant_tool_layer.dart';
import 'local_ai_chat.dart';
import 'local_ai_provider.dart';

/// Result of one Assistant user turn (tool loop + final text).
class AssistantTurnResult {
  const AssistantTurnResult({
    required this.text,
    this.toolsUsed = const [],
    this.errorCode,
    this.errorMessage,
    this.cancelled = false,
  });

  final String text;
  final List<String> toolsUsed;
  final String? errorCode;
  final String? errorMessage;
  final bool cancelled;

  bool get ok => errorCode == null && !cancelled;
}

/// Controlled read-only tool-calling loop for Pulse Assistant.
///
/// Flow: user → LocalAiProvider → allowlisted tools → PulseService IPC → LLM.
class AssistantOrchestrator {
  AssistantOrchestrator({
    required this.tools,
    this.maxToolIterations = 6,
  });

  final AssistantToolLayer tools;
  final int maxToolIterations;

  /// Runs one user message against [provider]/[modelId].
  Future<AssistantTurnResult> runTurn({
    required LocalAiProvider provider,
    required String modelId,
    required List<LocalAiChatMessage> history,
    required String userMessage,
    LocalAiCancelToken? cancelToken,
    void Function(String delta)? onTextDelta,
    void Function(String activityLabel)? onToolActivity,
    bool stream = true,
  }) async {
    final token = cancelToken ?? LocalAiCancelToken();
    final toolsUsed = <String>[];
    final toolDefs = [
      for (final t in tools.listTools())
        LocalAiToolDefinition(
          name: t.name,
          description: t.description,
          parameters: t.inputSchema,
        ),
    ];

    final messages = <LocalAiChatMessage>[
      LocalAiChatMessage.system(AssistantSystemPrompt.value),
      ...history,
      LocalAiChatMessage.user(userMessage),
    ];

    try {
      for (var iteration = 0; iteration < maxToolIterations; iteration++) {
        token.throwIfCancelled();

        final turn = await provider.chat(
          LocalAiChatRequest(
            modelId: modelId,
            messages: messages,
            tools: toolDefs,
            stream: stream && iteration == 0,
            cancelToken: token,
            onTextDelta: onTextDelta,
          ),
        );

        token.throwIfCancelled();

        if (!turn.hasToolCalls) {
          final text = (turn.content ?? '').trim();
          if (text.isEmpty) {
            return AssistantTurnResult(
              text: '',
              toolsUsed: toolsUsed,
              errorCode: 'EMPTY_RESPONSE',
              errorMessage:
                  'The local model returned an empty reply. Try again or pick another model.',
            );
          }
          return AssistantTurnResult(text: text, toolsUsed: toolsUsed);
        }

        // Append assistant tool-call message, then execute each call.
        messages.add(
          LocalAiChatMessage.assistant(
            turn.content,
            toolCalls: turn.toolCalls,
          ),
        );

        for (final call in turn.toolCalls) {
          token.throwIfCancelled();
          final name = AssistantToolAllowlist.normalize(call.name);

          if (!AssistantToolAllowlist.isAllowed(name) ||
              AssistantToolAllowlist.looksDangerous(call.name)) {
            messages.add(
              LocalAiChatMessage.toolResult(
                toolCallId: call.id,
                toolName: call.name,
                content: jsonToolDenied(call.name),
              ),
            );
            continue;
          }

          onToolActivity?.call(assistantToolActivityLabel(name));
          toolsUsed.add(name);

          final result = await tools.invoke(name, arguments: call.arguments);
          token.throwIfCancelled();

          messages.add(
            LocalAiChatMessage.toolResult(
              toolCallId: call.id,
              toolName: name,
              content: result.toLlmContent(),
            ),
          );
        }

        // Subsequent turns collect final text without streaming partial tool chatter.
        stream = true;
      }

      return AssistantTurnResult(
        text: '',
        toolsUsed: toolsUsed,
        errorCode: 'TOOL_LOOP_LIMIT',
        errorMessage:
            'Stopped after too many diagnostic tool rounds. Try a narrower question.',
      );
    } on LocalAiCancelledException {
      return AssistantTurnResult(
        text: '',
        toolsUsed: toolsUsed,
        cancelled: true,
        errorCode: 'CANCELLED',
        errorMessage: 'Cancelled',
      );
    } on LocalAiChatException catch (e) {
      return AssistantTurnResult(
        text: '',
        toolsUsed: toolsUsed,
        errorCode: e.code ?? 'PROVIDER_ERROR',
        errorMessage: e.message,
      );
    } catch (e) {
      return AssistantTurnResult(
        text: '',
        toolsUsed: toolsUsed,
        errorCode: 'UNEXPECTED',
        errorMessage: 'Something went wrong talking to the local model.',
      );
    }
  }

  static String jsonToolDenied(String toolName) {
    return '{"ok":false,"errorCode":"TOOL_NOT_ALLOWED",'
        '"errorMessage":"Tool \\"$toolName\\" is not available to Pulse Assistant."}';
  }
}
