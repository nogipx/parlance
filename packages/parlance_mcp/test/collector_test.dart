@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parlance_mcp/collector_host.dart';
import 'package:rpc_dart/logger.dart';
import 'package:rpc_dart_log/rpc_dart_log.dart';
import 'package:test/test.dart';

import '../bin/src/collector.dart';
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
      final adapter = CollectorHost(
        host: f.host,
        principal: agent,
        logs: logs,
        app: 'notes',
        device: 'phone',
        address: Uri.parse('ws://127.0.0.1:$port'),
      );
      addTearDown(adapter.close);
      Future<Map<String, dynamic>> waitForHost() async {
        final agent = _Agent(
          await Socket.connect(
            InternetAddress(path, type: InternetAddressType.unix),
            0,
          ),
        );
        try {
          await _until(() async => (await agent.hosts()).isNotEmpty);
          return (await agent.hosts()).single;
        } finally {
          await agent.close();
        }
      }

      final before = await waitForHost();
      await first.stop();
      running = null;
      final second = make(port);
      await second.start();
      running = second;
      expect((await waitForHost())['device'], before['device']);
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
    final address = Uri.parse(
      'ws://127.0.0.1:${collector.boundPort}/diagnostics?project=notes',
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
