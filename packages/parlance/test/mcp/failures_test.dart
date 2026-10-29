@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parlance/mcp.dart';
import 'package:parlance/mcp_io.dart';
import 'package:test/test.dart';

/// What an MCP server meets from the world: a client that sends what is
/// not JSON-RPC, a tool or its list that fails, a client gone. Each is
/// answered or let go, and the server goes on.
void main() {
  group('a session', () {
    late StreamController<String> input;
    late List<Map<String, Object?>> out;
    late FutureOr<List<McpTool>> Function() tools;
    late McpSession session;

    setUp(() {
      input = StreamController<String>();
      out = [];
      tools = () => [
        McpTool(
          name: 'ok',
          description: 'answers',
          run: (_) async => const McpResult('fine'),
        ),
        McpTool(
          name: 'bad',
          description: 'throws',
          run: (_) async => throw StateError('broken'),
        ),
      ];
      session = McpSession(
        input: input.stream,
        output: (l) => out.add(jsonDecode(l) as Map<String, Object?>),
        tools: () => tools(),
      );
    });
    tearDown(() async {
      await session.close();
      await input.close();
    });

    Future<Map<String, Object?>> answer(Object id) async {
      for (var i = 0; i < 50; i++) {
        if (out.where((m) => m['id'] == id).firstOrNull case final m?) {
          return m;
        }
        await Future<void>.delayed(Duration.zero);
      }
      fail('no answer to $id');
    }

    void send(Object? m) => input.add(m is String ? m : jsonEncode(m));

    Map<String, Object?> request(Object id, String method, [Object? p]) => {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?p,
    };

    test('what is not JSON is told so, and it goes on', () async {
      send('{"jsonrpc": "2.0", "id": 1, "method": ');
      send('ping, please');
      send(request(2, 'ping'));
      expect((await answer(2))['result'], isEmpty);
      expect(
        [
          for (final m in out)
            if (m['id'] == null) (m['error'] as Map)['code'],
        ],
        [-32700, -32700],
      );
    });

    test('params or arguments of another type are an error of that '
        'request', () async {
      send(request(1, 'tools/call', ['ok']));
      send(request(2, 'tools/call', {'name': 'ok', 'arguments': 'all'}));
      send(request(3, 'tools/call', {'name': 'ok'}));
      expect((await answer(1))['error'], isNotNull);
      expect((await answer(2))['error'], isNotNull);
      expect(((await answer(3))['result'] as Map)['isError'], isFalse);
    });

    test('a batch of what is no request answers the requests in it', () async {
      send([
        1,
        'x',
        null,
        request(7, 'ping'),
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      ]);
      expect((await answer(7))['result'], isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(out, hasLength(1), reason: 'nothing for a notification');
    });

    test(
      'a method there is not, a tool there is not, a tool that throws',
      () async {
        send(request(1, 'resources/list'));
        send(request(2, 'tools/call', {'name': 'none'}));
        send(request(3, 'tools/call', {'name': 'bad'}));
        expect(((await answer(1))['error'] as Map)['code'], -32601);
        expect(((await answer(2))['error'] as Map)['code'], -32602);
        final bad = (await answer(3))['result'] as Map;
        expect(bad['isError'], isTrue);
        expect('${bad['content']}', contains('broken'));
      },
    );

    test('a list of tools that fails is asked again next time', () async {
      final good = tools;
      tools = () => throw StateError('not now');
      send(request(1, 'tools/list'));
      expect(
        ((await answer(1))['error'] as Map)['message'],
        contains('not now'),
      );
      tools = good;
      send(request(2, 'tools/list'));
      expect(((await answer(2))['result'] as Map)['tools'], hasLength(2));
    });

    test('a client that cannot be written to is let go quietly', () async {
      final quiet = McpSession(
        input: Stream.fromIterable([jsonEncode(request(1, 'ping'))]),
        output: (_) => throw const SocketException('gone'),
        tools: () => const [],
      );
      await quiet.done.timeout(const Duration(seconds: 1));
    });

    test('an input that fails ends the session', () async {
      input.addError(const FormatException('bad bytes'));
      await session.done.timeout(const Duration(seconds: 1));
    });
  });

  group('the socket', () {
    late Directory dir;
    late String path;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('mcp');
      path = '${dir.path}/agent.sock';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    McpSocketServer server() => McpSocketServer(
      path: path,
      tools: () => [
        McpTool(
          name: 'ok',
          description: 'answers',
          run: (_) async => const McpResult('fine'),
        ),
      ],
    );

    Future<Socket> connect() => Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );

    Future<Map<String, Object?>> ping(Socket s) async {
      final answer = utf8.decoder
          .bind(s)
          .transform(const LineSplitter())
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .first;
      s.write('{"jsonrpc":"2.0","id":1,"method":"ping"}\n');
      return answer.timeout(const Duration(seconds: 2));
    }

    test('a file left at its path is replaced', () async {
      File(path).writeAsStringSync('left from before');
      final s = server();
      await s.start();
      addTearDown(s.stop);
      final agent = await connect();
      addTearDown(agent.destroy);
      expect((await ping(agent))['id'], 1);
    });

    test(
      'an agent that sends what is not UTF-8 ends its session alone',
      () async {
        final s = server();
        await s.start();
        addTearDown(s.stop);
        final bad = await connect();
        addTearDown(bad.destroy);
        bad.add([0xff, 0xfe, 0x0a]);
        await bad.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(s.sessions, 0);
        final good = await connect();
        addTearDown(good.destroy);
        expect((await ping(good))['id'], 1);
      },
    );

    test('stopped, it lets its agents go and leaves no socket', () async {
      final s = server();
      await s.start();
      final agent = await connect();
      final closed = agent.drain<void>().timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await s.stop();
      await closed;
      expect(FileSystemEntity.typeSync(path), FileSystemEntityType.notFound);
    });

    test(
      'a path it cannot take fails its start, and it may start again',
      () async {
        final missing = '${dir.path}/none/agent.sock';
        final s = McpSocketServer(path: missing, tools: () => const []);
        await expectLater(s.start(), throwsA(isA<SocketException>()));
        Directory('${dir.path}/none').createSync();
        await s.start();
        await s.stop();
      },
    );
  });
}
