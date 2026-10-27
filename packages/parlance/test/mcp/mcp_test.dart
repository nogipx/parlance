import 'dart:async';
import 'dart:convert';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:parlance/mcp.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:test/test.dart';

import '../registry/fixture.dart';

/// The registry fixture with a fact to hear.
final class Board extends Fixture {
  Board() {
    raid = r.defineFact(
      FactDescriptor(
        'platform.raid',
        type: const ObjectType({
          'from': Field(TextType()),
          'viewers': Field(IntType(min: 0)),
        }),
      ),
      by: const Principal('plugin', 'twitch'),
    );
  }

  late final RawFactEmitter raid;
}

/// A client of an MCP session in memory: sends requests, reads answers.
final class Client {
  Client(IBoard board, {bool commandTools = false}) {
    session = McpSession(
      input: _in.stream,
      output: (line) => _out.add(jsonDecode(line) as Map<String, Object?>),
      tools: () => parlanceTools(board, commandTools: commandTools),
      instructions: parlanceInstructions,
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

void main() {
  test('whether a command can run is told now, not when the tools were '
      'listed', () async {
    final f = Fixture();
    String? why = 'not yet';
    f.r.defineCommand(
      CommandDescriptor('x.go', callers: Callers.only(['agent'])),
      (_) {},
      available: () => why,
    );
    final c = Client(LocalBoard(f.r, by: agent), commandTools: true);
    addTearDown(c.close);
    final listed = await c.request('tools/list');
    expect('$listed', isNot(contains('not yet')));
    Future<Object?> now() async => [
      for (final x
          in (await c.json('describe', {'prefix': 'x.'}) as Map)['commands']
              as List)
        (x as Map)['unavailable'],
    ].single;
    expect(await now(), 'not yet');
    why = null;
    expect(await now(), isNull);
  });

  test(
    'tools are asked once until they change; a slow call holds no other',
    () async {
      final f = Fixture();
      final slow = Completer<void>();
      f.r.defineCommand(
        CommandDescriptor('x.slow', callers: Callers.only(['agent'])),
        (_) => slow.future,
      );
      final board = _Counting(LocalBoard(f.r, by: agent));
      final c = Client(board);
      addTearDown(c.close);
      await c.tools();
      await c.tools();
      expect(board.describes, 1);
      c.session.toolsChanged();
      await c.tools();
      expect(board.describes, 2);
      final pending = c.call('call', {'command': 'x.slow'});
      await c.request('ping').timeout(const Duration(seconds: 1));
      slow.complete();
      expect((await pending).error, isFalse);
    },
  );

  group('a local board', () {
    late Board f;
    late Client c;

    setUp(() {
      f = Board();
      c = Client(LocalBoard(f.r, by: agent));
    });
    tearDown(() => c.close());

    test('a state it may not read: no values, no why, not in a prefix '
        'read', () async {
      f.r
          .defineState(
            StateDescriptor(
              'studio.secret',
              type: const TextType(),
              readers: const Callers({'agent': Access.deny, '*': Access.allow}),
            ),
            by: owner,
          )
          .set('hush');
      final one = await c.call('read', {'state': 'studio.secret'});
      expect((one.error, one.text), (true, 'you may not read studio.secret'));
      final all = await c.call('read', {'prefix': 'studio.'});
      expect(all.error, isFalse);
      expect(all.text, isNot(contains('hush')));
      expect((await c.call('why', {'state': 'studio.secret'})).error, isTrue);
      await expectLater(
        LocalBoard(f.r, by: agent).readAll('studio.secret'),
        throwsStateError,
      );
      expect(await LocalBoard(f.r, by: user).readAll('studio.secret'), {
        null: 'hush',
      });
    });

    test('a fact it may not hear: no recent of it', () async {
      f.r
          .defineFact(
            FactDescriptor(
              'studio.whisper',
              type: const TextType(),
              readers: const Callers({'agent': Access.deny, '*': Access.allow}),
            ),
            by: owner,
          )
          .emit('psst');
      expect(
        (await c.call('recent_facts', {'fact': 'studio.whisper'})).error,
        isTrue,
      );
      await expectLater(
        LocalBoard(f.r, by: agent).recentFacts('studio.whisper', 5),
        throwsStateError,
      );
    });

    test('an entity that tells the type of its value shows it', () async {
      f.r.registerKind(
        EntityKind(
          'gauge',
          list: () => [
            EntityRef('g1', 'Gauge', {
              'type': const NumType(min: 0, max: 1).toJson(),
            }),
            const EntityRef('g2', 'Plain'),
          ],
        ),
      );
      final d = jsonDecode((await c.call('describe')).text) as Map;
      expect((d['entities'] as Map)['gauge'], [
        {
          'id': 'g1',
          'label': 'Gauge',
          'takes': {'type': 'number', 'minimum': 0, 'maximum': 1},
        },
        'g2 (Plain)',
      ]);
    });

    test('initialize tells the server and how to work', () async {
      final r = await c.request('initialize', {
        'protocolVersion': '2025-06-18',
      });
      final result = r['result'] as Map;
      expect(result['protocolVersion'], '2025-06-18');
      expect((result['serverInfo'] as Map)['name'], 'parlance');
      expect(result['instructions'], contains('describe first'));
    });

    test('the curated tools, and no command tools unless asked', () async {
      final names = await c.tools();
      expect(names, ['describe', 'read', 'call', 'recent_facts', 'why']);
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

    test('why tells the last change and the calls that led to it', () async {
      await c.call('call', {
        'command': 'audio.mute',
        'params': {'on': true},
      });
      final why = await c.json('why', {'state': 'audio.muted'}) as Map;
      expect(why['value'], true);
      expect((why['changed'] as Map)['by'], 'host/studio');
      expect(((why['trail'] as List).first as Map)['call'], 'audio.mute');
      expect(((why['trail'] as List).first as Map)['by'], 'agent/claude');
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
    late Board f;
    late RegistryResponder session;
    late RpcPeerEndpoint responder;
    late RpcPeerEndpoint caller;
    late RegistryMirror mirror;
    late Client c;

    setUp(() async {
      f = Board();
      final (client, server) = RpcChannelTransport.pair();
      responder = RpcPeerEndpoint(transport: server);
      session = RegistryResponder(responder, f.r, principal: agent);
      responder
        ..registerServiceContract(session)
        ..start();
      caller = RpcPeerEndpoint(transport: client)..start();
      final sc = ParlanceClient(caller);
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
      expect(((why['trail'] as List).first as Map)['by'], 'agent/claude');
      f.raid.emit({'from': 'b', 'viewers': 1});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        (await c.json('recent_facts', {'fact': 'platform.raid'}) as List),
        hasLength(1),
      );
    });

    test('a read right after a call reads what it wrote', () async {
      for (final scene in ['test', 'break', 'main']) {
        await c.call('call', {
          'command': 'studio.show',
          'params': {'scene': scene},
        });
        expect(await c.json('read', {'state': 'studio.program'}), scene);
      }
    });

    test(
      'the connection gone: reads say so, a call is lost with its id',
      () async {
        await c.tools();
        await responder.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final read = await c.call('read', {'state': 'studio.program'});
        expect(read.error, isTrue);
        expect(read.text, contains('not reachable'));
        final call = await c.call('call', {
          'command': 'studio.show',
          'params': {'scene': 'test'},
          'id': 'mine',
        });
        expect(call.error, isTrue);
        expect(call.text, contains('id "mine"'));
      },
    );

    test('a copy that cannot catch up with a call says so on read', () async {
      // The mirror follows another registry: it never reaches the call.
      final other = Board();
      final (c2, s2) = RpcChannelTransport.pair();
      final otherResponder = RpcPeerEndpoint(transport: s2);
      final otherSession = RegistryResponder(
        otherResponder,
        other.r,
        principal: agent,
      );
      otherResponder
        ..registerServiceContract(otherSession)
        ..start();
      final otherCaller = RpcPeerEndpoint(transport: c2)..start();
      final lagging = RegistryMirror()..follow(ParlanceClient(otherCaller));
      addTearDown(() async {
        await lagging.dispose();
        otherSession.close();
        await otherCaller.close();
        await otherResponder.close();
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final board = RemoteBoard(
        ParlanceClient(caller),
        lagging,
        catchUp: const Duration(milliseconds: 50),
      );
      await board.call('studio.show', {'scene': 'break'});
      await expectLater(
        board.readAll('studio.program'),
        throwsA(isA<BoardBehind>()),
      );
    });

    test('a word added later is a catalog change the tools follow', () async {
      final seen = <void>[];
      final sub = RemoteBoard(
        ParlanceClient(caller),
        mirror,
      ).catalogChanges.listen(seen.add);
      f.r.defineFact(FactDescriptor('x.new', type: const AnyType()), by: owner);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(seen, isNotEmpty);
      await sub.cancel();
    });
  });
}

/// A board that counts how often its catalog is asked.
final class _Counting implements IBoard {
  _Counting(this.inner);
  final IBoard inner;
  int describes = 0;

  @override
  Future<Map<String, Object?>> describe() {
    describes++;
    return inner.describe();
  }

  @override
  Future<Map<String?, Object?>> readAll(String state) => inner.readAll(state);

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
  }) => inner.call(command, params, id: id);

  @override
  Future<List<FactMessage>> recentFacts(String fact, int n) =>
      inner.recentFacts(fact, n);

  @override
  Future<Explanation> why(String state, {String? key}) =>
      inner.why(state, key: key);

  @override
  Stream<void> get catalogChanges => inner.catalogChanges;
}
