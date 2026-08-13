import 'dart:convert';

import '../local_ai_chat.dart';
import '../local_ai_http.dart';
import '../local_ai_provider.dart';
import '../local_ai_types.dart';

/// Ollama localhost API — tags + `/api/chat` with tools.
///
/// Default base: `http://127.0.0.1:11434`
/// Does not start Ollama, pull models, or run installers.
class OllamaProvider implements LocalAiProvider {
  OllamaProvider({
    LocalAiHttpClient? http,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 2),
    this.chatTimeout = const Duration(seconds: 120),
  })  : _http = http ?? const DartLocalAiHttpClient(),
        baseUri = baseUri ?? Uri.parse('http://127.0.0.1:11434') {
    DartLocalAiHttpClient.assertLocalhost(this.baseUri);
  }

  final LocalAiHttpClient _http;
  final Duration timeout;
  final Duration chatTimeout;

  @override
  final Uri baseUri;

  @override
  String get id => 'ollama';

  @override
  String get displayName => 'Ollama';

  @override
  bool get isLocal => true;

  @override
  Future<LocalAiProviderStatus> probe() async {
    final uri = baseUri.replace(path: '/api/tags');
    try {
      final response = await _http.get(uri, timeout: timeout);
      if (response.statusCode == 404) {
        return LocalAiProviderStatus.unavailable(
          detail: 'Ollama API not found',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LocalAiProviderStatus.error(
          message: 'HTTP ${response.statusCode}',
          detail: 'Ollama returned HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return LocalAiProviderStatus.error(
          message: 'Malformed Ollama response',
          detail: 'Expected a JSON object from /api/tags',
        );
      }
      final rawModels = decoded['models'];
      if (rawModels == null) {
        return LocalAiProviderStatus.error(
          message: 'Malformed Ollama response',
          detail: 'Missing "models" array',
        );
      }
      if (rawModels is! List) {
        return LocalAiProviderStatus.error(
          message: 'Malformed Ollama response',
          detail: '"models" must be an array',
        );
      }

      final models = <LocalAiModel>[];
      for (final item in rawModels) {
        if (item is! Map) continue;
        final name = (item['name'] ?? item['model'])?.toString().trim();
        if (name == null || name.isEmpty) continue;
        final details = item['details'];
        final meta = <String, Object?>{
          if (item['size'] != null) 'size': item['size'],
          if (item['digest'] != null) 'digest': item['digest'],
          if (item['modified_at'] != null) 'modified_at': item['modified_at'],
          if (details is Map) ...{
            if (details['family'] != null) 'family': details['family'],
            if (details['parameter_size'] != null)
              'parameter_size': details['parameter_size'],
            if (details['quantization_level'] != null)
              'quantization_level': details['quantization_level'],
            if (details['format'] != null) 'format': details['format'],
          },
        };
        models.add(
          LocalAiModel(id: name, displayName: name, metadata: meta),
        );
      }

      if (models.isEmpty) {
        return LocalAiProviderStatus.noModels(
          detail: 'Ollama is running but no models are installed',
        );
      }
      return LocalAiProviderStatus.ready(
        models: models,
        detail: 'Ollama · ${models.length} model(s)',
      );
    } catch (e) {
      if (isLocalAiConnectionFailure(e)) {
        return LocalAiProviderStatus.notFound(
          detail: 'Ollama is not running on localhost',
        );
      }
      return LocalAiProviderStatus.error(
        message: e.toString(),
        detail: 'Ollama probe failed',
      );
    }
  }

  @override
  Future<LocalAiChatTurn> chat(LocalAiChatRequest request) async {
    request.cancelToken?.throwIfCancelled();
    final uri = baseUri.replace(path: '/api/chat');
    final body = <String, Object?>{
      'model': request.modelId,
      'stream': request.stream,
      'messages': [
        for (final m in request.messages) _encodeMessage(m),
      ],
      if (request.tools.isNotEmpty)
        'tools': [
          for (final t in request.tools)
            {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            },
        ],
    };

    try {
      if (request.stream) {
        return await _chatStreaming(uri, body, request);
      }
      final response = await _http.post(
        uri,
        body: jsonEncode(body),
        timeout: request.timeout,
      );
      request.cancelToken?.throwIfCancelled();
      return _parseNonStream(response);
    } on LocalAiCancelledException {
      rethrow;
    } on LocalAiChatException {
      rethrow;
    } catch (e) {
      if (isLocalAiConnectionFailure(e)) {
        throw LocalAiChatException(
          'Ollama is not available on localhost.',
          code: 'PROVIDER_UNAVAILABLE',
        );
      }
      throw LocalAiChatException(
        'Could not complete the Ollama chat request.',
        code: 'PROVIDER_ERROR',
      );
    }
  }

  Future<LocalAiChatTurn> _chatStreaming(
    Uri uri,
    Map<String, Object?> body,
    LocalAiChatRequest request,
  ) async {
    final buffer = StringBuffer();
    String? content;
    List<LocalAiToolCall> toolCalls = const [];
    String? finishReason;

    final response = await _http.post(
      uri,
      body: jsonEncode(body),
      timeout: request.timeout,
      onStreamChunk: (chunk) {
        request.cancelToken?.throwIfCancelled();
        buffer.write(chunk);
        // Parse complete NDJSON lines as they arrive.
        final text = buffer.toString();
        final lines = text.split('\n');
        // Keep incomplete last line in buffer conceptually via re-parse of full.
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          Map<String, dynamic>? obj;
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is Map<String, dynamic>) {
              obj = decoded;
            } else if (decoded is Map) {
              obj = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {
            continue;
          }
          if (obj == null) continue;
          final message = obj['message'];
          if (message is Map) {
            final delta = message['content']?.toString();
            if (delta != null && delta.isNotEmpty) {
              content = (content ?? '') + delta;
              request.onTextDelta?.call(delta);
            }
            final calls = message['tool_calls'];
            if (calls is List && calls.isNotEmpty) {
              toolCalls = _parseToolCalls(calls);
            }
          }
          if (obj['done'] == true) {
            finishReason = obj['done_reason']?.toString();
          }
        }
      },
    );

    request.cancelToken?.throwIfCancelled();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalAiChatException(
        'Ollama returned HTTP ${response.statusCode}.',
        code: 'HTTP_ERROR',
      );
    }

    // Prefer last complete object if streaming parse missed tool calls.
    if (toolCalls.isEmpty || (content == null || content!.isEmpty)) {
      try {
        final lastLine = response.body
            .trim()
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .lastOrNull;
        if (lastLine != null) {
          final decoded = jsonDecode(lastLine);
          if (decoded is Map) {
            final message = decoded['message'];
            if (message is Map) {
              content ??= message['content']?.toString();
              final calls = message['tool_calls'];
              if (calls is List && calls.isNotEmpty) {
                toolCalls = _parseToolCalls(calls);
              }
            }
            finishReason ??= decoded['done_reason']?.toString();
          }
        }
      } catch (_) {
        // keep streamed content
      }
    }

    return LocalAiChatTurn(
      content: content,
      toolCalls: toolCalls,
      finishReason: finishReason,
    );
  }

  LocalAiChatTurn _parseNonStream(LocalAiHttpResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalAiChatException(
        'Ollama returned HTTP ${response.statusCode}.',
        code: 'HTTP_ERROR',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const LocalAiChatException(
        'Malformed response from Ollama.',
        code: 'MALFORMED_RESPONSE',
      );
    }
    final message = decoded['message'];
    if (message is! Map) {
      throw const LocalAiChatException(
        'Malformed response from Ollama.',
        code: 'MALFORMED_RESPONSE',
      );
    }
    final content = message['content']?.toString();
    final calls = message['tool_calls'];
    return LocalAiChatTurn(
      content: content,
      toolCalls: calls is List ? _parseToolCalls(calls) : const [],
      finishReason: decoded['done_reason']?.toString(),
    );
  }

  Map<String, Object?> _encodeMessage(LocalAiChatMessage m) {
    switch (m.role) {
      case LocalAiMessageRole.system:
        return {'role': 'system', 'content': m.content ?? ''};
      case LocalAiMessageRole.user:
        return {'role': 'user', 'content': m.content ?? ''};
      case LocalAiMessageRole.assistant:
        return {
          'role': 'assistant',
          'content': m.content ?? '',
          if (m.toolCalls.isNotEmpty)
            'tool_calls': [
              for (final c in m.toolCalls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {
                    'name': c.name,
                    'arguments': c.arguments,
                  },
                },
            ],
        };
      case LocalAiMessageRole.tool:
        return {
          'role': 'tool',
          'content': m.content ?? '',
          if (m.toolName != null) 'tool_name': m.toolName,
          if (m.toolCallId != null) 'tool_call_id': m.toolCallId,
        };
    }
  }

  List<LocalAiToolCall> _parseToolCalls(List<dynamic> raw) {
    final out = <LocalAiToolCall>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? 'call_$i';
      final fn = item['function'];
      String? name;
      Map<String, Object?> args = const {};
      if (fn is Map) {
        name = fn['name']?.toString();
        args = _parseArgs(fn['arguments']);
      } else {
        name = item['name']?.toString();
        args = _parseArgs(item['arguments']);
      }
      if (name == null || name.isEmpty) continue;
      out.add(LocalAiToolCall(id: id, name: name, arguments: args));
    }
    return out;
  }

  Map<String, Object?> _parseArgs(Object? raw) {
    if (raw == null) return const {};
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const {};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }
}

extension<T> on Iterable<T> {
  T? get lastOrNull {
    if (isEmpty) return null;
    return last;
  }
}
