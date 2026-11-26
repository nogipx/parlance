import 'dart:async';
import 'dart:convert';

/// Multiplexes the window's requests on one MCP connection. Tool-list
/// notifications can arrive between replies, and replies can arrive out of order.
final class ConsoleClient {
  ConsoleClient(Stream<String> input, this._out) {
    _input = input.listen(
      _receive,
      onDone: close,
      onError: (Object _) => close(),
    );
  }

  final StringSink _out;
  late final StreamSubscription<String> _input;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _next = 0;
  bool closed = false;
  int catalogRevision = 0;

  void _receive(String line) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    if (message['method'] == 'notifications/tools/list_changed') {
      catalogRevision++;
    }
    final waiting = _pending.remove(message['id']);
    if (waiting == null) return;
    if (message['error'] case final Map<String, dynamic> error) {
      waiting.completeError(StateError(error['message'].toString()));
    } else {
      waiting.complete(message['result'] as Map<String, dynamic>);
    }
  }

  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, Object?>? params,
  ]) async {
    if (closed) throw StateError('Collector disconnected');
    final id = ++_next;
    final waiting = _pending[id] = Completer<Map<String, dynamic>>();
    try {
      _out.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': ?params,
        }),
      );
      return await waiting.future.timeout(const Duration(seconds: 30));
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> initialize() async {
    final result = await request('initialize', {
      'protocolVersion': '2025-06-18',
      'clientInfo': {'name': 'Parlance Console', 'version': '0.1.0'},
      'capabilities': <String, Object?>{},
    });
    if (result['protocolVersion'] != '2025-06-18') {
      throw StateError('Unsupported MCP version');
    }
    _out.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
  }

  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final result = await request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    if (result['isError'] == true) throw StateError(resultText(result));
    return result;
  }

  static String resultText(Map<String, dynamic> result) =>
      ((result['content'] as List<dynamic>).first
              as Map<String, dynamic>)['text']
          as String;

  void close() {
    if (closed) return;
    closed = true;
    unawaited(_input.cancel());
    for (final pending in _pending.values) {
      pending.completeError(StateError('Collector disconnected'));
    }
    _pending.clear();
  }
}
