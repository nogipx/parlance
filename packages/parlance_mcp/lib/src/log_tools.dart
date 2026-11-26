import 'package:parlance_mcp/parlance_mcp.dart';
import 'package:rpc_dart_log/rpc_dart_log_server.dart';

List<McpTool> logTools(
  Iterable<LogCollectorSession> sessions,
  LogCollectorMcpBuffer buffer,
) => [
  McpTool(
    name: 'rpc_log_sources',
    description:
        'Connected devices, scope statistics, recent errors, trace prefixes and buffer cursor.',
    run: (_) async => McpResult(
      buffer.sources(sessions.toList()),
      structuredContent: {
        'cursor': buffer.cursor,
        'devices': [
          for (final session in sessions)
            {'device': session.label, 'app': session.app},
        ],
      },
    ),
  ),
  McpTool(
    name: 'rpc_log_get_logs',
    description:
        'Read buffered records in chronological order. Filter by device, scope or trace. Use cursor to tail.',
    properties: const {
      'count': {
        'type': 'integer',
        'description': 'Maximum records, default 50, up to 500.',
      },
      'level': {
        'type': 'string',
        'enum': [
          'internal',
          'trace',
          'debug',
          'info',
          'warning',
          'error',
          'fatal',
        ],
      },
      'scope': {'type': 'string', 'description': 'Scope prefix.'},
      'device': {
        'type': 'string',
        'description': 'Case-insensitive device substring.',
      },
      'traceId': {'type': 'string', 'description': 'Trace ID prefix.'},
      'message': {
        'type': 'string',
        'description': 'Case-insensitive message regex.',
      },
      'since': {
        'type': 'string',
        'description': 'Relative duration or local clock time.',
      },
      'cursor': {
        'type': 'integer',
        'description': 'Only newer records. Overrides since.',
      },
      'type': {
        'type': 'string',
        'enum': ['event', 'span'],
      },
      'collapse': {
        'type': 'boolean',
        'description': 'Collapse repeating sequences.',
      },
      'no_data': {'type': 'boolean', 'description': 'Omit structured data.'},
      'context': {
        'type': 'integer',
        'description': 'Surrounding lines per match, up to 20.',
      },
    },
    run: (args) async => McpResult(buffer.getLogs(args)),
  ),
];
