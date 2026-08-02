import '../mcp_launch_resolver.dart';
import 'mcp_client_provider.dart';

/// Future ChatGPT desktop/MCP registration — not available in M7.
class ChatGptMcpProvider implements McpClientProvider {
  const ChatGptMcpProvider();

  @override
  McpClientId get id => McpClientId.chatgpt;

  @override
  Future<McpClientDetection> detect() async {
    return const McpClientDetection(
      installed: false,
      configPath: null,
      detail: 'ChatGPT MCP registration is reserved for a future release',
    );
  }

  @override
  Future<bool> isRegistered(McpLaunchCommand launch) async => false;

  @override
  Future<McpRegistrationResult> register(McpLaunchCommand launch) async {
    return const McpRegistrationResult(
      ok: false,
      message: 'ChatGPT registration is not supported yet',
    );
  }

  @override
  Future<McpRegistrationResult> unregister() async {
    return const McpRegistrationResult(
      ok: false,
      message: 'ChatGPT registration is not supported yet',
    );
  }
}
