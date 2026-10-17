import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal HTTP client for local AI runtimes on this PC.
///
/// Diagnostic data must never leave this PC, so the client connects only to
/// literal loopback addresses, never follows redirects and never uses a proxy.
/// There is no opt-out. Does not bind sockets or expose ports.
/// Where local AI runtimes are reached: always 127.0.0.1, only the port can
/// change. There is deliberately no way to enter another address.
abstract final class LocalAiLoopback {
  static const int ollamaDefaultPort = 11434;
  static const int lmStudioDefaultPort = 1234;
  static const int minPort = 1;
  static const int maxPort = 65535;

  static bool isValidPort(int port) => port >= minPort && port <= maxPort;

  static Uri uri(int port) {
    if (!isValidPort(port)) {
      throw ArgumentError.value(port, 'port', 'Must be $minPort-$maxPort');
    }
    return Uri(scheme: 'http', host: '127.0.0.1', port: port);
  }

  /// `127.0.0.1:<port>` for messages shown to the user.
  static String label(Uri baseUri) => '${baseUri.host}:${baseUri.port}';
}

class LocalAiHttpResponse {
  const LocalAiHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

abstract class LocalAiHttpClient {
  Future<LocalAiHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 2),
    Map<String, String> headers = const {},
  });

  Future<LocalAiHttpResponse> post(
    Uri uri, {
    required String body,
    Duration timeout = const Duration(seconds: 120),
    Map<String, String> headers = const {},
    void Function(String chunk)? onStreamChunk,
  });
}

class DartLocalAiHttpClient implements LocalAiHttpClient {
  const DartLocalAiHttpClient();

  /// Literal loopback addresses only. Names such as `localhost` are refused
  /// because the hosts file can point them at another machine.
  static const allowedHosts = {'127.0.0.1', '::1'};

  static void assertLocalhost(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError('Only http(s) loopback URIs are allowed: $uri');
    }
    if (!allowedHosts.contains(uri.host.toLowerCase())) {
      throw ArgumentError(
        'Refusing non-loopback AI endpoint: ${uri.host}',
      );
    }
  }

  @override
  Future<LocalAiHttpResponse> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 2),
    Map<String, String> headers = const {},
  }) async {
    return _send('GET', uri, timeout: timeout, headers: headers);
  }

  @override
  Future<LocalAiHttpResponse> post(
    Uri uri, {
    required String body,
    Duration timeout = const Duration(seconds: 120),
    Map<String, String> headers = const {},
    void Function(String chunk)? onStreamChunk,
  }) async {
    return _send(
      'POST',
      uri,
      timeout: timeout,
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
      body: body,
      onStreamChunk: onStreamChunk,
    );
  }

  Future<LocalAiHttpResponse> _send(
    String method,
    Uri uri, {
    required Duration timeout,
    Map<String, String> headers = const {},
    String? body,
    void Function(String chunk)? onStreamChunk,
  }) async {
    assertLocalhost(uri);
    final client = HttpClient()
      // Connect straight to the loopback address, even when the system or
      // environment defines a proxy.
      ..findProxy = (_) => 'DIRECT';
    client.connectionTimeout = timeout;
    client.idleTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      // A redirect could point at another machine; callers see the 3xx
      // status as an HTTP error instead.
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) {
        final bytes = utf8.encode(body);
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      if (onStreamChunk != null) {
        final buffer = StringBuffer();
        await for (final chunk in response.transform(utf8.decoder)) {
          buffer.write(chunk);
          onStreamChunk(chunk);
        }
        return LocalAiHttpResponse(
          statusCode: response.statusCode,
          body: buffer.toString(),
        );
      }
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return LocalAiHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// Connection failures that mean “runtime not listening”.
bool isLocalAiConnectionFailure(Object error) {
  if (error is TimeoutException) return true;
  if (error is SocketException) return true;
  if (error is HttpException) return true;
  if (error is HandshakeException) return true;
  return false;
}
