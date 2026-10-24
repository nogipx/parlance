import 'dart:async';
import 'dart:convert';

/// What a tool gives back: text, and pictures (PNG, base64 in MCP).
final class McpResult {
  const McpResult(this.text, {this.images = const [], this.error = false});

  const McpResult.error(this.text) : images = const [], error = true;

  /// [value] as indented JSON, for the agent to read.
  factory McpResult.json(Object? value) =>
      McpResult(const JsonEncoder.withIndent(' ').convert(value));

  final String text;

  /// PNG bytes.
  final List<List<int>> images;

  /// The tool could not do it: [text] says why, for the agent to fix.
  final bool error;

  Map<String, Object?> toMcp() => {
    'content': [
      {'type': 'text', 'text': text},
      for (final i in images)
        {'type': 'image', 'data': base64Encode(i), 'mimeType': 'image/png'},
    ],
    'isError': error,
  };
}

/// A tool an agent can call: its name, what it does, the JSON Schema of its
/// arguments, and what it does with them.
final class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.run,
    this.properties = const {},
    this.required = const [],
  });

  final String name;
  final String description;

  /// The JSON Schema of each argument, by name.
  final Map<String, Map<String, Object?>> properties;
  final List<String> required;
  final Future<McpResult> Function(Map<String, Object?> args) run;

  Map<String, Object?> toMcp() => {
    'name': name,
    'description': description,
    'inputSchema': {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    },
  };
}

/// One MCP session over lines of JSON-RPC 2.0: the stdio transport, or a
/// socket carrying it the same way. Tools only; it asks nothing back.
final class McpSession {
  McpSession({
    required Stream<String> input,
    required this.output,
    required this.tools,
    this.name = 'switchboard',
    this.version = '0.1.0',
    this.instructions,
    this.log,
  }) {
    _sub = input.listen(
      _line,
      onDone: _end,
      onError: (Object _) => _end(),
      cancelOnError: true,
    );
  }

  /// Writes one line (no newline in it) to the client.
  final void Function(String line) output;

  /// The tools there are now; asked on every list and call.
  final FutureOr<List<McpTool>> Function() tools;
  final String name;
  final String version;

  /// What the agent is told when it connects.
  final String? instructions;

  /// Where tool calls are noted.
  final void Function(String line)? log;

  static const versions = ['2025-06-18', '2025-03-26', '2024-11-05'];

  late final StreamSubscription<String> _sub;
  final Completer<void> _done = Completer();

  /// Ends when the client goes.
  Future<void> get done => _done.future;

  void _end() {
    if (!_done.isCompleted) _done.complete();
  }

  void _send(Map<String, Object?> m) {
    if (_done.isCompleted) return;
    try {
      output(jsonEncode(m));
    } on Object catch (_) {}
  }

  Future<void> _line(String line) async {
    if (line.trim().isEmpty) return;
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      _send(_error(null, -32700, 'not JSON'));
      return;
    }
    for (final m in message is List ? message : [message]) {
      if (m is! Map) continue;
      final reply = await handle(m.cast<String, Object?>());
      if (reply != null) _send(reply);
    }
  }

  /// The tools are others now: the client lists them again.
  void toolsChanged() =>
      _send({'jsonrpc': '2.0', 'method': 'notifications/tools/list_changed'});

  /// The answer to one JSON-RPC message; null for a notification.
  Future<Map<String, Object?>?> handle(Map<String, Object?> m) async {
    final id = m['id'];
    final method = m['method'];
    if (method is! String || id == null) return null;
    final params = (m['params'] as Map?)?.cast<String, Object?>() ?? const {};
    switch (method) {
      case 'initialize':
        final asked = params['protocolVersion'];
        return _result(id, {
          'protocolVersion': versions.contains(asked) ? asked : versions.first,
          'capabilities': {
            'tools': {'listChanged': true},
          },
          'serverInfo': {'name': name, 'version': version},
          'instructions': ?instructions,
        });
      case 'ping':
        return _result(id, const <String, Object?>{});
      case 'tools/list':
        return _result(id, {
          'tools': [for (final t in await tools()) t.toMcp()],
        });
      case 'tools/call':
        final name = params['name'];
        final tool = (await tools()).where((t) => t.name == name).firstOrNull;
        if (tool == null) return _error(id, -32602, 'no tool "$name"');
        final args =
            (params['arguments'] as Map?)?.cast<String, Object?>() ?? const {};
        log?.call('mcp: $name');
        try {
          return _result(id, (await tool.run(args)).toMcp());
        } on Object catch (e) {
          return _result(id, McpResult.error('$e').toMcp());
        }
      default:
        return _error(id, -32601, 'no method "$method"');
    }
  }

  static Map<String, Object?> _result(Object id, Object? result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  /// Stops reading; the client is not told.
  Future<void> close() async {
    await _sub.cancel();
    _end();
  }
}
