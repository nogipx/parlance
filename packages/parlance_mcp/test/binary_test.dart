@Tags(['process'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parlance/tools.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_socket/rpc_dart_socket.dart';
import 'package:test/test.dart';

const agent = Principal('agent', 'claude');

/// The binary itself: a host serves its registry on a Unix socket, an agent
/// speaks MCP to parlance-mcp on stdio.
void main() {
  test(
    'parlance-mcp serves a host over a socket on stdio',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final r = Registry();
      addTearDown(r.dispose);
      final house = r.participant(
        const Principal('house'),
        vocabularies: [const WordSet.open('house')],
      );
      final focus = house.defineState(
        StateDescriptor('house.focus', type: const TextType()),
      );
      house.defineCommand(
        CommandDescriptor(
          'house.show',
          params: const RecordType({'room': Field(TextType())}),
          callers: const Callers({'agent': Access.allow}),
        ),
        (c) => focus.set(c.params['room']),
      );
      final dir = Directory.systemTemp.createTempSync('sbmcp');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/r.sock';
      final sessions = <RemoteSession>[];
      final server = RpcSocketServer(
        address: RpcSocketAddress.unix(path),
        mode: RpcPeerMode((endpoint) {
          final s = r.participant(agent).serve(endpoint);
          sessions.add(s);
        }),
      );
      await server.start();
      addTearDown(server.stop);

      final mcp = await Process.start(Platform.resolvedExecutable, [
        'run',
        'bin/parlance_mcp.dart',
        '--connect',
        'unix:$path',
      ]);
      addTearDown(mcp.kill);
      final answers = StreamController<Map<String, Object?>>.broadcast();
      mcp.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) => answers.add(jsonDecode(l) as Map<String, Object?>));
      mcp.stderr.transform(utf8.decoder).listen((_) {});
      var id = 0;
      Future<Map<String, Object?>> request(String method, [Object? params]) {
        final n = ++id;
        final answer = answers.stream.firstWhere((m) => m['id'] == n);
        mcp.stdin.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': n,
            'method': method,
            'params': ?params,
          }),
        );
        return answer.timeout(const Duration(seconds: 60));
      }

      final init = await request('initialize', {
        'protocolVersion': '2025-06-18',
      });
      expect(
        ((init['result'] as Map)['serverInfo'] as Map)['name'],
        'parlance',
      );
      // The feed may take a moment to arrive.
      List<String> names = [];
      for (var i = 0; i < 20 && !names.contains('describe'); i++) {
        final list = await request('tools/list');
        names = [
          for (final t in (list['result'] as Map)['tools'] as List)
            (t as Map)['name'] as String,
        ];
        if (!names.contains('describe')) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      expect(names, contains('call'));
      final call = await request('tools/call', {
        'name': 'call',
        'arguments': {
          'command': 'house.show',
          'params': {'room': 'break'},
        },
      });
      expect((call['result'] as Map)['isError'], isFalse);
      expect(house.read('house.focus'), 'break');
      expect(sessions, hasLength(1));
      await mcp.stdin.close();
      expect(await mcp.exitCode.timeout(const Duration(seconds: 20)), 0);
    },
  );
  test(
    'an agent given no tools while the host was away is told when it comes',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final r = Registry();
      addTearDown(r.dispose);
      final dir = Directory.systemTemp.createTempSync('sbmcp');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/r.sock';

      final mcp = await Process.start(Platform.resolvedExecutable, [
        'run',
        'bin/parlance_mcp.dart',
        '--connect',
        'unix:$path',
      ]);
      addTearDown(mcp.kill);
      final lines = StreamController<Map<String, Object?>>.broadcast();
      mcp.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) => lines.add(jsonDecode(l) as Map<String, Object?>));
      mcp.stderr.transform(utf8.decoder).listen((_) {});
      var id = 0;
      Future<Map<String, Object?>> request(String method, [Object? params]) {
        final n = ++id;
        final answer = lines.stream.firstWhere((m) => m['id'] == n);
        mcp.stdin.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': n,
            'method': method,
            'params': ?params,
          }),
        );
        return answer.timeout(const Duration(seconds: 60));
      }

      Future<List<Object?>> tools() async =>
          ((await request('tools/list'))['result'] as Map)['tools'] as List;

      await request('initialize', {'protocolVersion': '2025-06-18'});
      expect(await tools(), isEmpty, reason: 'no host yet');

      final told = lines.stream
          .firstWhere((m) => m['method'] == 'notifications/tools/list_changed')
          .timeout(const Duration(seconds: 30));
      final server = RpcSocketServer(
        address: RpcSocketAddress.unix(path),
        mode: RpcPeerMode((endpoint) => r.participant(agent).serve(endpoint)),
      );
      await server.start();
      addTearDown(server.stop);
      await told;
      expect(await tools(), isNotEmpty);
      await mcp.stdin.close();
      expect(await mcp.exitCode.timeout(const Duration(seconds: 20)), 0);
    },
  );
}
