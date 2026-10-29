@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parlance/mcp.dart';
import 'package:parlance/mcp_io.dart';
import 'package:test/test.dart';

/// An agent on the other end of the socket.
final class _Agent {
  _Agent._(this.socket) {
    utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen((l) => _lines.add(jsonDecode(l) as Map<String, Object?>));
  }

  static Future<_Agent> connect(String path) async => _Agent._(
    await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    ),
  );

  final Socket socket;
  final _lines = StreamController<Map<String, Object?>>.broadcast();
  var _id = 0;

  Future<Map<String, Object?>> request(String method, [Object? params]) {
    final id = ++_id;
    final answer = _lines.stream.firstWhere((m) => m['id'] == id);
    socket.write(
      '${jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params})}\n',
    );
    return answer;
  }

  Future<List<String>> tools() async => [
    for (final t
        in ((await request('tools/list'))['result'] as Map)['tools'] as List)
      (t as Map)['name'] as String,
  ];

  Future<void> close() => socket.close();
}

McpTool _tool(String name) => McpTool(
  name: name,
  description: 'a tool',
  run: (_) async => const McpResult('ok'),
);

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('mcp');
    path = '${dir.path}/agent.sock';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('agents connect, list the tools, and hear when they change', () async {
    var tools = [_tool('one')];
    final counts = <int>[];
    final server = McpSocketServer(
      path: path,
      tools: () => tools,
      name: 'house',
      instructions: 'be kind',
      onSessions: counts.add,
    );
    await server.start();
    expect(
      (FileStat.statSync(path).mode & 0x1FF).toRadixString(8),
      '600',
      reason: 'the owner alone',
    );
    final agent = await _Agent.connect(path);
    final init = await agent.request('initialize', {
      'protocolVersion': '2025-06-18',
    });
    expect(((init['result'] as Map)['serverInfo'] as Map)['name'], 'house');
    expect(await agent.tools(), ['one']);
    tools = [_tool('one'), _tool('two')];
    expect(await agent.tools(), ['one'], reason: 'kept until told');
    server.toolsChanged();
    expect(await agent.tools(), ['one', 'two']);
    expect(server.sessions, 1);
    await agent.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.sessions, 0);
    expect(counts, [1, 0]);
    await server.stop();
    expect(File(path).existsSync(), isFalse);
  });
  test('an agent gone before it hears what it was told ends its session '
      'alone, the host going on', () async {
    final server = McpSocketServer(path: path, tools: () => [_tool('one')]);
    await server.start();
    final agent = await _Agent.connect(path);
    expect(await agent.tools(), ['one']);
    agent.socket.destroy();
    server.toolsChanged();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.sessions, 0);
    await server.stop();
  });
}
