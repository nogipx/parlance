@Tags(['process'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_socket/rpc_dart_socket.dart';
import 'package:switchboard/remote.dart';
import 'package:test/test.dart';

import '../links/fixture.dart';

/// The binary itself: a host serves its registry on a Unix socket, an agent
/// speaks MCP to switchboard-mcp on stdio.
void main() {
  test(
    'switchboard-mcp serves a host over a socket on stdio',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final f = LinksFixture();
      final dir = Directory.systemTemp.createTempSync('sbmcp');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/r.sock';
      final sessions = <RegistryResponder>[];
      final server = RpcSocketServer(
        address: RpcSocketAddress.unix(path),
        mode: RpcResponderMode((endpoint) {
          final s = RegistryResponder(f.r, principal: agent);
          sessions.add(s);
          endpoint.registerServiceContract(s);
        }),
      );
      await server.start();
      addTearDown(server.stop);

      final mcp = await Process.start(Platform.resolvedExecutable, [
        'run',
        'bin/switchboard_mcp.dart',
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
        'switchboard',
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
          'command': 'studio.show',
          'params': {'scene': 'break'},
        },
      });
      expect((call['result'] as Map)['isError'], isFalse);
      expect(f.r.read('studio.program'), 'break');
      expect(sessions, hasLength(1));
      await mcp.stdin.close();
      expect(await mcp.exitCode.timeout(const Duration(seconds: 20)), 0);
    },
  );
}
