import 'dart:async';
import 'dart:convert';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:switchboard/mcp.dart';
import 'package:switchboard/registry.dart';
import 'package:switchboard/remote.dart';
import 'package:test/test.dart';

import '../links/fixture.dart';

/// A client of an MCP session in memory: sends requests, reads answers.
final class Client {
  Client(Board board, {bool commandTools = false}) {
    session = McpSession(
      input: _in.stream,
      output: (line) => _out.add(jsonDecode(line) as Map<String, Object?>),
      tools: () => switchboardTools(board, commandTools: commandTools),
      instructions: switchboardInstructions,
    );
    _out.stream.listen((m) {
      if (m['id'] case final int id) _waiting.remove(id)?.complete(m);
      if (m['method'] != null) notes.add(m['method'] as String);
    });
  }

  late final McpSession session;
  final _in = StreamController<String>();
  final _out = StreamController<Map<String, Object?>>();
  final _waiting = <int, Completer<Map<String, Object?>>>{};
  final notes = <String>[];
  var _id = 0;

  Future<Map<String, Object?>> request(String method, [Object? params]) {
    final id = ++_id;
    final c = _waiting[id] = Completer();
    _in.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    return c.future;
  }

  Future<List<String>> tools() async {
    final r = await request('tools/list');
    return [
      for (final t in ((r['result'] as Map)['tools'] as List))
        (t as Map)['name'] as String,
    ];
  }

  /// Calls [tool]; answers its text, and whether it was an error.
  Future<({String text, bool error})> call(
    String tool, [
    Map<String, Object?> args = const {},
  ]) async {
    final r = await request('tools/call', {'name': tool, 'arguments': args});
    final result = r['result'] as Map;
    return (
      text: ((result['content'] as List).first as Map)['text'] as String,
      error: result['isError'] == true,
    );
  }

  Future<Object?> json(
    String tool, [
    Map<String, Object?> args = const {},
  ]) async {
    final r = await call(tool, args);
    if (r.error) throw StateError(r.text);
    return jsonDecode(r.text);
  }

  Future<void> close() async {
    await session.close();
    await _in.close();
  }
}

const break_ = {
  'id': 'break',
  'when': [
    {'manual': <String, Object?>{}},
  ],
  'do': [
    {
      'call': 'studio.show',
      'params': {'scene': 'break'},
    },
  ],
};

void main() {
  group('a local board', () {
    late LinksFixture f;
    late Client c;

    setUp(() {
      f = LinksFixture();
      c = Client(LocalBoard(f.r, by: agent));
    });
    tearDown(() => c.close());

    test('initialize tells the server and how to work', () async {
      final r = await c.request('initialize', {
        'protocolVersion': '2025-06-18',
      });
      final result = r['result'] as Map;
      expect(result['protocolVersion'], '2025-06-18');
      expect((result['serverInfo'] as Map)['name'], 'switchboard');
      expect(result['instructions'], contains('describe first'));
    });

    test('the curated tools, and no command tools unless asked', () async {
      final names = await c.tools();
      expect(names, [
        'describe',
        'read',
        'call',
        'recent_facts',
        'why',
        'layers',
        'links',
        'link_guide',
        'link_check',
        'link_upsert',
        'link_remove',
        'links_set',
        'link_try',
        'link_press',
      ]);
      final withCommands = Client(
        LocalBoard(f.r, by: agent),
        commandTools: true,
      );
      addTearDown(withCommands.close);
      expect(
        await withCommands.tools(),
        containsAll(['studio_show', 'audio_mute']),
      );
      expect(
        await withCommands.tools(),
        isNot(contains('audio_gain_set')),
        reason: 'not for agents',
      );
    });

    test(
      'describe: only what the agent may call, with schemas and entities',
      () async {
        final d = await c.json('describe') as Map;
        final commands = {
          for (final x in d['commands'] as List) (x as Map)['name']: x,
        };
        expect(commands.keys, contains('studio.show'));
        expect(commands.keys, isNot(contains('audio.gain.set')));
        final show = commands['studio.show'] as Map;
        expect(
          ((show['params'] as Map)['properties'] as Map)['scene'],
          containsPair('enum', ['main', 'break', 'test']),
        );
        expect(show['sets'], 'studio.program');
        expect(show['interceptable'], isTrue);
        expect((d['entities'] as Map)['scene'], contains('main (main)'));
        final audio = await c.json('describe', {'prefix': 'audio.'}) as Map;
        expect(
          [for (final x in audio['states'] as List) (x as Map)['name']],
          ['audio.muted', 'audio.gain'],
        );
      },
    );

    test('call does it; a refusal says why; read tells the state', () async {
      expect(
        (await c.call('call', {
          'command': 'studio.show',
          'params': {'scene': 'break'},
        })).error,
        isFalse,
      );
      expect(await c.json('read', {'state': 'studio.program'}), 'break');
      final bad = await c.call('call', {
        'command': 'studio.show',
        'params': {'scene': 'nowhere'},
      });
      expect(bad.error, isTrue);
      expect(bad.text, startsWith('invalidParams'));
    });

    test(
      'why tells the last change, the calls that led to it, the layers',
      () async {
        await c.call('call', {
          'command': 'audio.mute',
          'params': {'on': true},
        });
        final why = await c.json('why', {'state': 'audio.muted'}) as Map;
        expect(why['value'], true);
        expect((why['changed'] as Map)['by'], 'host:studio');
        expect(((why['trail'] as List).first as Map)['call'], 'audio.mute');
        expect(((why['trail'] as List).first as Map)['by'], 'agent:claude');
        f.r.pushLayer(
          'audio.muted',
          value: false,
          owner: 'quiet',
          by: Principal.system,
        );
        await pumpEventQueue();
        final layers = await c.json('layers') as List;
        expect((layers.single as Map)['owner'], 'quiet');
      },
    );

    test('links: check, upsert, press, remove', () async {
      final missing = await c.json('link_check', {
        'link': {
          'id': 'later',
          'when': [
            {'fact': 'plugin.thing'},
          ],
          'do': <Object?>[],
        },
      }) as Map;
      expect(missing['missing'], ['plugin.thing']);
      expect((await c.call('link_upsert', {'link': break_})).error, isFalse);
      final links = await c.json('links') as Map;
      expect((links['own'] as List).single, containsPair('id', 'break'));
      expect(
        (links['statuses'] as Map)['break'],
        containsPair('state', 'active'),
      );
      expect(await c.json('link_press', {'id': 'break'}), {'ran': true});
      expect(f.r.read('studio.program'), 'break');
      expect((await c.call('link_remove', {'id': 'break'})).error, isFalse);
      expect((await c.json('links') as Map)['own'], isEmpty);
      final bad = await c.call('links_set', {
        'links': [
          {
            'id': 'x',
            'when': [
              {'fact': 'Not A Name'},
            ],
            'do': <Object?>[],
          },
        ],
      });
      expect(bad.error, isTrue);
      expect((await c.call('link_guide')).text, contains('Reaction:'));
    });

    test('recent facts', () async {
      f.raid.emit({'from': 'a', 'viewers': 3});
      await pumpEventQueue();
      final facts =
          await c.json('recent_facts', {'fact': 'platform.raid'}) as List;
      expect((facts.single as Map)['payload'], {'from': 'a', 'viewers': 3});
    });
  });

  group('a remote board', () {
    late LinksFixture f;
    late RegistryResponder session;
    late RpcResponderEndpoint responder;
    late RpcCallerEndpoint caller;
    late RegistryMirror mirror;
    late Client c;

    setUp(() async {
      f = LinksFixture();
      final (client, server) = RpcChannelTransport.pair();
      session = RegistryResponder(f.r, principal: agent);
      responder = RpcResponderEndpoint(transport: server)
        ..registerServiceContract(session)
        ..start();
      caller = RpcCallerEndpoint(transport: client);
      final sc = SwitchboardClient(caller);
      mirror = RegistryMirror()..follow(sc);
      c = Client(RemoteBoard(sc, mirror));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    tearDown(() async {
      await c.close();
      await mirror.dispose();
      session.close();
      await caller.close();
      await responder.close();
    });

    test('the same tools work over remote, as the session may', () async {
      final d = await c.json('describe') as Map;
      final names = [for (final x in d['commands'] as List) (x as Map)['name']];
      expect(names, contains('studio.show'));
      expect(names, isNot(contains('audio.gain.set')));
      await c.call('call', {
        'command': 'studio.show',
        'params': {'scene': 'test'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await c.json('read', {'state': 'studio.program'}), 'test');
      final why = await c.json('why', {'state': 'studio.program'}) as Map;
      expect(((why['trail'] as List).first as Map)['by'], 'agent:claude');
      expect((await c.call('link_upsert', {'link': break_})).error, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        ((await c.json('links') as Map)['own'] as List).single,
        containsPair('id', 'break'),
      );
      expect(await c.json('link_press', {'id': 'break'}), {'ran': true});
      f.raid.emit({'from': 'b', 'viewers': 1});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        (await c.json('recent_facts', {'fact': 'platform.raid'}) as List),
        hasLength(1),
      );
      expect(await c.json('layers'), isEmpty);
    });

    test(
      'a link engine added later is a catalog change the tools follow',
      () async {
        final seen = <void>[];
        final sub = RemoteBoard(
          SwitchboardClient(caller),
          mirror,
        ).catalogChanges.listen(seen.add);
        f.r.defineFact(
          FactDescriptor('x.new', type: const AnyType()),
          by: owner,
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(seen, isNotEmpty);
        await sub.cancel();
      },
    );
  });
}
