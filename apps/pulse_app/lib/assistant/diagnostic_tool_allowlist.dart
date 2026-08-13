import 'assistant_tools.dart';

/// Explicit Assistant-safe tool allowlist (read-only diagnostics only).
///
/// Wire names match PulseMCP `V1_TOOLS` where applicable.
/// `report_export` is intentionally excluded — it writes files.
/// Mutating / shell / install tools must never appear here.
abstract final class AssistantToolAllowlist {
  static const tools = <AssistantToolDescriptor>[
    AssistantToolDescriptor(
      name: 'mcp_self',
      description:
          'Pulse Assistant / MCP self status: versions and connection health. Observation only.',
    ),
    AssistantToolDescriptor(
      name: 'system_health',
      description:
          'Full or sectioned Windows system health snapshot (CPU, memory, GPU, storage, network). Read-only.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'sections': {
            'type': 'array',
            'items': {
              'type': 'string',
              'enum': ['cpu', 'memory', 'gpu', 'storage', 'network', 'static'],
            },
          },
        },
      },
    ),
    AssistantToolDescriptor(
      name: 'system_cpu',
      description: 'CPU usage and related metrics. Read-only.',
    ),
    AssistantToolDescriptor(
      name: 'system_memory',
      description: 'Memory / RAM usage metrics. Read-only.',
    ),
    AssistantToolDescriptor(
      name: 'system_gpu',
      description: 'GPU utilization and related metrics. Read-only.',
    ),
    AssistantToolDescriptor(
      name: 'system_storage',
      description: 'Disk / volume usage. Read-only.',
    ),
    AssistantToolDescriptor(
      name: 'system_network',
      description: 'Network adapter throughput summary. Read-only.',
    ),
    AssistantToolDescriptor(
      name: 'process_list',
      description:
          'List running processes with CPU/memory (top consumers). Read-only.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50},
          'sortBy': {
            'type': 'string',
            'enum': ['cpu', 'memory', 'name'],
          },
        },
      },
    ),
    AssistantToolDescriptor(
      name: 'process_search',
      description: 'Search processes by name substring. Read-only.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50},
        },
        'required': ['query'],
      },
    ),
    AssistantToolDescriptor(
      name: 'process_details',
      description: 'Details for a single process by PID. Read-only.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'pid': {'type': 'integer', 'minimum': 1},
        },
        'required': ['pid'],
      },
    ),
    AssistantToolDescriptor(
      name: 'timeline_list',
      description: 'Recent Windows timeline / event log summaries. Read-only.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50},
        },
      },
    ),
    AssistantToolDescriptor(
      name: 'timeline_search',
      description: 'Search recent timeline events by text. Read-only.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50},
        },
        'required': ['query'],
      },
    ),
    AssistantToolDescriptor(
      name: 'diagnostics_snapshot',
      description:
          'PulseService pipeline diagnostics snapshot (service health). Read-only.',
    ),
    AssistantToolDescriptor(
      name: 'service_status',
      description:
          'PulseService identity and SCM status only (not full Windows services catalog). Read-only.',
    ),
  ];

  static final Set<String> names = {for (final t in tools) t.name};

  static bool isAllowed(String toolName) => names.contains(normalize(toolName));

  static String normalize(String name) =>
      name.trim().toLowerCase().replaceAll('.', '_').replaceAll('-', '_');

  /// Reject known mutating / dangerous names even if somehow requested.
  static const rejectedPatterns = <String>[
    'shell',
    'powershell',
    'cmd',
    'exec',
    'run_command',
    'write_file',
    'delete_file',
    'registry',
    'kill',
    'stop_service',
    'start_service',
    'install',
    'download',
    'report_export',
    'mutate',
  ];

  static bool looksDangerous(String toolName) {
    final n = normalize(toolName);
    for (final p in rejectedPatterns) {
      if (n.contains(p)) return true;
    }
    return false;
  }
}
