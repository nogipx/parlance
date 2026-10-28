import 'dart:async';
import 'dart:convert';

import '../registry/types.dart';
import '../registry/shapes.dart';
import 'schema.dart';

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

  /// A tool whose arguments are [params] (SPEC §16): its schema is theirs,
  /// with each field's description, and [run] gets them checked and typed.
  /// What does not pass is the agent's error, by path ("ops.2.frame:
  /// missing"); the tool's description says only what the schema cannot.
  static McpTool typed<P>({
    required String name,
    required String description,
    required RecordShape<P> params,
    required Future<McpResult> Function(P args) run,
  }) {
    final type = params.type;
    final schema = jsonSchema(type);
    return McpTool(
      name: name,
      description: description,
      properties: {
        for (final e in (schema['properties']! as Map).entries)
          e.key as String: (e.value as Map).cast<String, Object?>(),
      },
      required: [for (final r in schema['required']! as List) r as String],
      run: (args) async {
        final P typed;
        try {
          typed = params.fromJson(type.check(args, const _Free()));
        } on TypeMismatch catch (e) {
          return McpResult.error('$e');
        } on Object catch (e) {
          return McpResult.error('$e');
        }
        return run(typed);
      },
    );
  }

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
    this.name = 'parlance',
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

  /// The tools there are now: asked once, and again after [toolsChanged]
  /// or when asking failed.
  final FutureOr<List<McpTool>> Function() tools;

  Future<List<McpTool>>? _tools;

  Future<List<McpTool>> _current() {
    final asked = _tools ??= Future.sync(tools);
    return asked.catchError((Object e) {
      if (identical(_tools, asked)) _tools = null;
      throw e;
    });
  }

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
    // Each message is answered when it is done: a long tool call does not
    // hold the others back (replies carry their ids).
    for (final m in message is List ? message : [message]) {
      if (m is! Map) continue;
      final request = m.cast<String, Object?>();
      unawaited(
        handle(request).then(
          (reply) {
            if (reply != null) _send(reply);
          },
          onError: (Object e) {
            if (request['id'] case final Object id) {
              _send(_error(id, -32603, '$e'));
            }
          },
        ),
      );
    }
  }

  /// The tools are others now: they are asked again, and the client lists
  /// them again.
  void toolsChanged() {
    _tools = null;
    _send({'jsonrpc': '2.0', 'method': 'notifications/tools/list_changed'});
  }

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
          'tools': [for (final t in await _current()) t.toMcp()],
        });
      case 'tools/call':
        final name = params['name'];
        final tool = (await _current())
            .where((t) => t.name == name)
            .firstOrNull;
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

/// A tool's arguments are checked alone: no kinds or host types to ask.
final class _Free implements ITypeContext {
  const _Free();

  @override
  bool hasKind(String kind) => true;

  @override
  bool hasEntity(String kind, String id) => true;

  @override
  String? checkCustom(String name, Object? value) => null;
}
