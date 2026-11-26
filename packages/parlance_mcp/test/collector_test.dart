@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parlance_mcp/collector_host.dart';
import 'package:parlance_mcp/src/host_logs.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_websocket/rpc_dart_websocket.dart';
import 'package:rpc_dart_log/rpc_dart_log.dart';
import 'package:test/test.dart';

import 'package:parlance_mcp/io.dart';
import 'fixture.dart';

final class _Agent {
  _Agent(this.socket)
    : lines = StreamIterator(
        utf8.decoder.bind(socket).transform(const LineSplitter()),
      );
  final Socket socket;
  final StreamIterator<String> lines;
  int next = 0;

  Future<Map<String, dynamic>> request(String method, [Object? params]) async {
    final id = ++next;
    socket.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'id': id,
        'params': ?params,
      }),
    );
    while (await lines.moveNext()) {
      final reply = jsonDecode(lines.current) as Map<String, dynamic>;
      if (reply['id'] == id) return reply;
    }
    throw StateError('agent socket closed');
  }

  Future<String> call(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    final reply = await request('tools/call', {
      'name': name,
      'arguments': args,
    });
    return reply['result']['content'][0]['text'] as String;
  }

  Future<List<Map<String, dynamic>>> hosts() async =>
      (jsonDecode(await call('hosts')) as List).cast<Map<String, dynamic>>();

  Future<void> close() async {
    socket.destroy();
    await lines.cancel();
  }
}

Future<void> _until(Future<bool> Function() check) async {
  final clock = Stopwatch()..start();
  while (!await check()) {
    if (clock.elapsed > const Duration(seconds: 8)) fail('condition timed out');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  test(
    'a second console attaches without stopping the shared collector',
    () async {
      final dir = await Directory.systemTemp.createTemp('console');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/local.sock';
      final owner = await LocalCollector.open(path, port: 0);
      final peer = await LocalCollector.open(path, port: 0);
      await peer.close();
      final first = _Agent(owner.socket);
      expect(await first.hosts(), isEmpty);
      await owner.close();
      expect(await FileSystemEntity.type(path), FileSystemEntityType.notFound);
    },
  );

  test(
    'host reconnects to a restarted collector without a new adapter',
    () async {
      final dir = Directory.systemTemp.createTempSync('pmcp');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/agent.sock';
      Collector make(int port) =>
          Collector(socket: path, bind: '127.0.0.1', port: port);
      final first = make(0);
      await first.start();
      final port = first.boundPort;
      Collector? running = first;
      addTearDown(() => running?.stop());
      final f = Fixture();
      addTearDown(f.host.dispose);
      final logs = LogController(outputs: []);
      addTearDown(logs.dispose);
      var connections = 0;
      final testZone = Zone.current;
      final adapter = IOOverrides.runZoned(
        () => CollectorHost(
          host: f.host,
          principal: agent,
          logs: logs,
          app: 'notes',
          device: 'phone',
          address: Uri.parse('ws://127.0.0.1:$port'),
        ),
        socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) {
          connections++;
          return testZone.run(
            () => Socket.startConnect(
              host,
              port,
              sourceAddress: sourceAddress,
              sourcePort: sourcePort,
            ),
          );
        },
      );
      addTearDown(adapter.close);
      Future<Map<String, dynamic>> waitForHost(String message) async {
        final agent = _Agent(
          await Socket.connect(
            InternetAddress(path, type: InternetAddressType.unix),
            0,
          ),
        );
        try {
          await _until(() async => (await agent.hosts()).isNotEmpty);
          await _until(
            () async =>
                (await agent.call('rpc_log_get_logs')).contains(message),
          );
          return (await agent.hosts()).single;
        } finally {
          await agent.close();
        }
      }

      logs.scope('sync').warning('before restart');
      final before = await waitForHost('before restart');
      expect(connections, 1);
      await first.stop();
      running = null;
      logs.scope('sync').warning('during outage');
      final second = make(port);
      await second.start();
      running = second;
      expect((await waitForHost('during outage'))['device'], before['device']);
      expect(connections, 2);
    },
  );

  test(
    'replayed batches across sockets add only previously unseen records; v1 hosts still register',
    () async {
      final dir = await Directory.systemTemp.createTemp('pmcp');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/agent.sock';
      final collector = Collector(socket: path, bind: '127.0.0.1', port: 0);
      await collector.start();
      addTearDown(collector.stop);
      final client = _Agent(
        await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        ),
      );
      addTearDown(client.close);
      final f = Fixture();
      addTearDown(f.host.dispose);
      final uri = Uri.parse(
        'ws://127.0.0.1:${collector.boundPort}?app=notes&device=phone',
      );

      Future<void> visit(String protocol, List<String> messages) async {
        final peer = RpcPeerEndpoint(
          transport: await RpcWebSocketCallerTransport.connect(
            uri,
            protocols: [protocol],
          ),
        );
        final session = f.host.serve(agent, peer);
        peer.start();
        try {
          await _until(() async => (await client.hosts()).length == 1);
          if (messages.isNotEmpty) {
            await peer.unary<LogBatch, LogBatch>(
              serviceName: 'CollectorLogs',
              methodName: 'append',
              request: LogBatch({
                'first': 1,
                'records': [
                  for (final message in messages)
                    LogEvent(
                      scope: 'sync',
                      level: RpcLogLevel.info,
                      message: message,
                    ).toJson(),
                ],
              }),
              requestCodec: LogBatch.codec,
              responseCodec: LogBatch.codec,
            );
          } else {
            // In v1 only the separate log connection registers a log source.
            expect(
              await client.call('rpc_log_sources'),
              isNot(contains('phone [notes]')),
            );
          }
        } finally {
          session.dispose();
          await peer.close();
        }
        await _until(() async => (await client.hosts()).isEmpty);
      }

      await visit('parlance.host.v1', []);
      await visit('parlance.host.v2', ['first batch']);
      await visit('parlance.host.v2', ['first batch', 'next batch']);
      final logs = await client.call('rpc_log_get_logs');
      expect(logs, contains('Found 2 records'));
      expect(logs, contains('first batch'));
      expect(logs, contains('next batch'));
    },
  );

  test('one agent reads independent hosts and retained log streams', () async {
    final dir = Directory.systemTemp.createTempSync('pmcp');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/agent.sock';
    final collector = Collector(socket: path, bind: '127.0.0.1', port: 0);
    await collector.start();
    addTearDown(collector.stop);

    Future<_Agent> connectAgent() async {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      final client = _Agent(socket);
      addTearDown(client.close);
      return client;
    }

    final client = await connectAgent();
    expect(await client.hosts(), isEmpty);
    final lan = await CollectorLan.start(
      InternetAddress.loopbackIPv4,
      collectorPort: collector.boundPort,
      plainPort: 0,
    );
    addTearDown(lan.close);
    final address = lan.android.replace(
      path: '/diagnostics',
      queryParameters: {'project': 'notes'},
    );
    final plainOutput = LogCollectorOutput(
      uri: address,
      device: const DeviceInfo(name: 'worker', app: 'jobs'),
    );
    final worker = LogController(outputs: [plainOutput]);
    addTearDown(worker.dispose);
    addTearDown(plainOutput.dispose);
    final span = worker.scope('jobs').startSpan('background task');
    span.end();
    await _until(
      () async => (await client.call('rpc_log_get_logs', {
        'device': 'worker',
        'traceId': span.traceId,
        'type': 'span',
      })).contains('background task'),
    );
    expect(await client.hosts(), isEmpty);
    CollectorHost attach(String device, {bool commands = false}) {
      final f = Fixture()..focus.set(device);
      addTearDown(f.host.dispose);
      final logs = LogController(outputs: []);
      addTearDown(logs.dispose);
      final connection = CollectorHost(
        host: f.host,
        principal: agent,
        address: address,
        app: 'notes',
        device: device,
        commandTools: commands,
        shareJournal: device == 'desktop',
        logs: logs,
      );
      addTearDown(connection.close);
      logs.scope('sync').warning('edit on $device');
      return connection;
    }

    final phone = attach('phone');
    attach('desktop', commands: true);
    await _until(() async => (await client.hosts()).length == 2);
    final entries = await client.hosts();
    final phoneHost = entries.singleWhere(
      (e) => (e['device'] as String).startsWith('phone/'),
    );
    final desktop = entries.singleWhere(
      (e) => (e['device'] as String).startsWith('desktop/'),
    );
    final prefix = phoneHost['prefix'];
    await _until(() async {
      final reply = await client.request('tools/list');
      final names = (reply['result']['tools'] as List).map(
        (t) => (t as Map)['name'],
      );
      expect(names, isNot(contains('${prefix}_call')));
      expect(names, isNot(contains('${prefix}_journal')));
      return names.contains('${prefix}_read') &&
          names.contains("${desktop['prefix']}_read");
    });
    const args = {'state': 'host/house/house.focus'};
    expect(jsonDecode(await client.call('${prefix}_read', args)), 'phone');
    expect(
      jsonDecode(await client.call("${desktop['prefix']}_read", args)),
      'desktop',
    );
    expect(
      jsonDecode(await client.call('${prefix}_why', args))['value'],
      'phone',
    );
    final called = await client.request('tools/call', {
      'name': "${desktop['prefix']}_call",
      'arguments': {
        'command': 'host/house/house.show',
        'params': {'room': 'break'},
      },
    });
    expect(called['result']['isError'], false);
    expect(desktop['journal'], true);
    final journalTool = "${desktop['prefix']}_journal";
    final page =
        jsonDecode(await client.call(journalTool)) as Map<String, dynamic>;
    final rows = (page['lines'] as List<dynamic>)
        .cast<String>()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final callRows = rows.where((r) => r['command'] == 'host/house/house.show');
    expect(
      callRows.map((r) => r['kind']),
      containsAllInOrder(['start', 'end']),
    );
    expect(
      callRows.every((r) => r['payloads'] == false && !r.containsKey('params')),
      true,
    );
    expect(
      rows
          .where((r) => r['kind'] == 'write')
          .every((r) => !r.containsKey('value')),
      true,
    );
    final next =
        jsonDecode(await client.call(journalTool, {'after': page['cursor']}))
            as Map<String, dynamic>;
    expect(next['lines'], isEmpty);
    expect(
      jsonDecode(await client.call("${desktop['prefix']}_read", args)),
      'break',
    );
    expect(jsonDecode(await client.call('${prefix}_read', args)), 'phone');
    final filter = {
      'device': phoneHost['device'],
      'level': 'warning',
      'scope': 'sync',
    };
    await _until(
      () async => (await client.call(
        'rpc_log_get_logs',
        filter,
      )).contains('edit on phone'),
    );
    expect(await client.call('rpc_log_sources'), contains(phoneHost['device']));
    await phone.close();
    await _until(() async => (await client.hosts()).length == 1);
    expect(
      await client.request('tools/call', {
        'name': '${prefix}_read',
        'arguments': args,
      }),
      contains('error'),
    );
    final other = await connectAgent();
    final logs = await other.call('rpc_log_get_logs', filter);
    expect(logs, contains('edit on phone'));
    expect(logs, isNot(contains('edit on desktop')));
  });
}
