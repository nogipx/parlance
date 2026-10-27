import 'dart:async';

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/src/remote/contract.dart' show parlanceProtocol;
import 'package:parlance/src/remote/participant.dart' show checkProtocol;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

const kittens = Principal('plugin', 'kittens');
const crew = Principal('user', 'local');
const someone = Principal('viewer', 'v1');

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

enum Lamp<T> implements IStateWord<T> {
  on<bool>('kittens.lamp');

  const Lamp(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const Plain(BoolType()) as Shape<T>;
  @override
  String? get key => null;
}

typedef Turn = ({bool on});

final _turn = RecordShape<Turn>(
  {'on': Part(Plain(BoolType()))},
  to: (t) => {'on': t.on},
  from: (m) => (on: m['on']! as bool),
);

enum LampCommand<P, R> implements ICommandWord<P, R> {
  turn<Turn, void>('kittens.lamp.turn');

  const LampCommand(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _turn as RecordShape<P>;
  @override
  Shape<R>? get returns => null;
}

enum Purr<T> implements IFactWord<T> {
  purred<Turn>('kittens.purred');

  const Purr(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => _turn as Shape<T>;
}

/// One owner's code: the same whether it runs in the host's process or
/// across a connection.
final class Lamps extends Owner {
  bool lit = false;
  late final StateWriterOf<bool> _on;
  late final FactEmitterOf<Turn> _purred;

  @override
  void define(IParticipant p) {
    _on = keep(p.state(Lamp.on).define());
    _purred = keep(p.fact(Purr.purred).define());
    keep(
      p.command(LampCommand.turn).define((c) {
        lit = c.params.on;
        _on.set(lit, cause: c.causeFor(kittens));
        _purred.emit(c.params, cause: c.causeFor(kittens));
      }, callers: Callers.only(['user'])),
    );
  }

  @override
  void sync() => _on.set(lit);

  void purr() => _purred.emit((on: lit));
}

void main() {
  late Registry r;
  RemoteSession? session;
  RpcPeerEndpoint? host;
  RpcClientConnection? connection;

  /// A connection in memory that does not come back once lost: the
  /// factory gives the one transport, and it does not reconnect.
  Future<RemoteParticipant> join({
    Set<String> namespaces = const {'kittens'},
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
    LogScope? log,
  }) {
    final (c, s) = RpcChannelTransport.memoryPair();
    final h = host = RpcPeerEndpoint(transport: s);
    session = r
        .participant(
          kittens,
          vocabularies: [for (final n in namespaces) WordSet.open(n)],
          rights: rights,
          access: access,
        )
        .serve(h);
    h.start();
    final link = connection = RpcClientConnection(
      transportFactory: (_) async => c,
      shouldReconnect: (_) => false,
    );
    return RemoteParticipant.join(link, log: log);
  }

  setUp(() => r = Registry(overriders: {'user'}));
  tearDown(() async {
    session?.close();
    await connection?.dispose();
    await host?.close();
    (session, connection, host) = (null, null, null);
    await r.dispose();
  });

  test(
    'it is the session\'s principal, in the session\'s namespaces',
    () async {
      final p = await join();
      expect(p.who, kittens);
      expect(p.namespaces, {'kittens'});
    },
  );

  test('the same owner works across a connection: its command is served, '
      'and what it writes and says follows from the call', () async {
    final lamps = Lamps();
    final p = await join();
    p.attach({'lamps': lamps});
    await p.flush();
    expect(r.read('kittens.lamp'), false);

    final crewSide = r.participant(crew);
    final done = await crewSide.command(LampCommand.turn).call((on: true));
    expect(done.ok, isTrue, reason: '$done');
    expect(r.read('kittens.lamp'), true);
    final change = r.lastChange('kittens.lamp')!;
    expect(change.cause.by, kittens.child('lamps'), reason: 'its part');
    expect(change.cause.parent, isNotNull, reason: 'it follows from the call');
    final purr = r.recent('kittens.purred').single;
    expect(purr.cause.parent, change.cause.parent);
    expect(p.state(Lamp.on).read(), true, reason: 'its own, as it wrote it');
    expect(crewSide.status('kittens.lamp.turn'), const WordReady());
  });

  test(
    'a group of owners works on a remote participant as on a local one',
    () async {
      final p = await join();
      final lamps = Lamps();
      p.attach({'lamps': lamps});
      await p.flush();
      expect(r.read('kittens.lamp'), false);
      lamps.lit = true;
      p.sync();
      await p.flush();
      expect(r.read('kittens.lamp'), true);
      await p.close();
      expect(r.stateDescriptor('kittens.lamp'), isNull);
    },
  );

  test('a part across a connection acts as itself on the host', () async {
    final p = await join();
    final lamps = Lamps();
    p.attach({'lamps': lamps});
    await p.flush();
    final part = kittens.child('lamps');
    expect(r.lastChange('kittens.lamp')!.cause.by, part);

    final records = <CallRecord>[];
    final sub = r.calls.listen(records.add);
    expect(
      (await r.call('kittens.lamp.turn', {'on': true}, by: crew)).ok,
      isTrue,
    );
    expect(r.lastChange('kittens.lamp')!.cause.by, part, reason: 'served');
    expect(r.recent('kittens.purred').last.cause.by, part);

    final ui = p.child('ui');
    final asked = await ui.call('kittens.lamp.turn', {'on': false});
    await settle();
    expect(asked, isA<CallRefused>(), reason: 'only the user calls it');
    expect(records.last.cause.by, kittens.child('ui'));
    expect(
      () => ui.call('kittens.lamp.turn', {}, cause: Cause(part)),
      throwsA(isA<NotPermitted>()),
      reason: 'not as a sibling',
    );

    ui.addGuard('quiet', (_) => 'quiet');
    await p.flush();
    expect(
      (await r.call('kittens.lamp.turn', {'on': true}, by: crew)).ok,
      isTrue,
      reason: 'ui\'s guard judges ui\'s commands only',
    );
    await sub.cancel();
  });

  test('across a connection a query changes nothing either', () async {
    final p = await join();
    final lamp = p.state(Lamp.on).define()..set(false);
    p.defineQuery(
      QueryDescriptor(
        'kittens.count',
        returns: const IntType(),
        askers: const Callers({'*': Access.allow}),
      ),
      (_) {
        lamp.set(true);
        return 1;
      },
    );
    await p.flush();
    final out = await r.call('kittens.count', {}, by: crew);
    expect(out, isA<CallFailed>());
    expect(out.whyNot, contains('kittens.count is a query'));
    await p.flush();
    expect(r.read('kittens.lamp'), false);
  });

  test('what it writes in one turn is one tick', () async {
    final p = await join();
    final lamp = p.state(Lamp.on).define();
    await p.flush();
    final ticks = <Tick>[];
    final sub = r.ticks.listen(ticks.add);
    lamp
      ..set(true)
      ..set(false)
      ..set(true);
    await p.flush();
    await settle();
    expect(ticks, hasLength(1));
    expect(r.read('kittens.lamp'), true);
    await sub.cancel();
  });

  test('outside its namespaces it is refused at once; what the host refuses '
      'comes after, to its errors', () async {
    final p = await join(
      rights: ParticipantRights(
        define: (_, d) => d is FactDescriptor ? 'no facts' : null,
      ),
    );
    expect(
      () => p.defineState(StateDescriptor('cart.x', type: const BoolType())),
      throwsA(isA<NotPermitted>()),
    );
    final errors = <ParticipantError>[];
    p.errors.listen(errors.add);
    p.fact(Purr.purred).define();
    await p.flush();
    await settle();
    expect(errors.single.code, 'permissionDenied');
    expect(errors.single.message, 'no facts');
    expect(r.factDescriptor('kittens.purred'), isNull);
  });

  test('a call it serves is a span in the host\'s trace, and how it goes '
      'is told', () async {
    final logs = LogController();
    final records = <LogRecord>[];
    logs.stream.listen(records.add);
    await r.dispose();
    r = Registry(overriders: {'user'}, log: logs.scope('host'));
    final p = await join(log: logs.scope('kittens'));
    p.attach({'lamps': Lamps()});
    await p.flush();
    expect(
      (await r.call('kittens.lamp.turn', {'on': true}, by: crew)).ok,
      isTrue,
    );
    await settle();
    final spans = records.whereType<LogSpan>();
    final there = spans.singleWhere((s) => s.scope == 'kittens.calls');
    final here = spans.singleWhere((s) => s.scope == 'host.calls');
    expect(there.name, 'kittens.lamp.turn');
    expect(there.traceId, here.traceId);
    expect(there.parentSpanId, here.spanId, reason: 'a child across it');
    final told = records.whereType<LogEvent>().map((e) => e.message);
    expect(told, contains('joined'));
    expect(told, contains('session opened'));
    logs.dispose();
  });

  test('its guard is asked in its turn', () async {
    final p = await join();
    var served = 0;
    p
        .command(LampCommand.turn)
        .define((_) => served++, callers: Callers.only(['user']));
    p.addGuard(
      'night',
      (c) => c.params['on'] == true ? 'the kittens sleep' : null,
    );
    await p.flush();

    final denied = await r.call('kittens.lamp.turn', {'on': true}, by: crew);
    expect(denied, isA<CallRefused>());
    expect((denied as CallRefused).code, Refusal.denied);
    expect(denied.reason, 'the kittens sleep');
    expect(denied.guard, 'plugin/kittens#night');
    expect(served, 0, reason: 'denied before the handler');
    expect(
      (await r.call('kittens.lamp.turn', {'on': false}, by: crew)).ok,
      isTrue,
    );
    expect(served, 1);
  });

  test('a command\'s availability follows what its check reads', () async {
    final p = await join();
    final lamp = p.state(Lamp.on).define()..set(false);
    p
        .command(LampCommand.turn)
        .define(
          (_) {},
          callers: Callers.only(['user']),
          available: () =>
              p.state(Lamp.on).read() == true ? 'already on' : null,
        );
    await p.flush();
    final crewSide = r.participant(crew);
    expect(crewSide.status('kittens.lamp.turn'), const WordReady());
    final seen = <WordStatus>[];
    final sub = crewSide.statusChanges('kittens.lamp.turn').listen(seen.add);
    lamp.set(true);
    await p.flush();
    await settle();
    expect(
      crewSide.status('kittens.lamp.turn'),
      const WordUnavailable('already on'),
    );
    expect(seen.last, const WordUnavailable('already on'));
    await sub.cancel();
  });

  test('it keeps a kind of entities and tells when they change', () async {
    final p = await join();
    final names = ['tom'];
    p.registerKind(
      EntityKind('kitten', list: () => [for (final n in names) EntityRef(n)]),
    );
    await p.flush();
    expect(r.hasEntity('kitten', 'tom'), isTrue);
    names.add('ivy');
    p.entitiesChanged('kitten');
    await p.flush();
    expect(r.hasEntity('kitten', 'ivy'), isTrue);
  });

  test('it speaks for another only when the host lets it', () async {
    final p = await join(
      rights: ParticipantRights(
        speakFor: (_, by, _) => by.kind == 'viewer' ? null : 'viewers only',
      ),
    );
    final errors = <ParticipantError>[];
    p.errors.listen(errors.add);
    final purred = p.fact(Purr.purred).define();
    purred.emit((on: true), cause: const Cause(someone));
    purred.emit((on: false), cause: const Cause(crew));
    await p.flush();
    await settle();
    expect(r.recent('kittens.purred').single.cause.by, someone);
    expect(errors.single.message, 'viewers only');
  });

  test('a value its state or fact cannot hold is refused at once, as in '
      'the host\'s process', () async {
    final p = await join();
    final lamp = p.defineState(
      StateDescriptor('kittens.lamp', type: const BoolType()),
    );
    final errors = <ParticipantError>[];
    p.errors.listen(errors.add);
    expect(() => lamp.set('on'), throwsA(isA<TypeMismatch>()));
    expect(() => lamp.set(true, key: 'a'), throwsArgumentError);
    final purr = p.defineFact(
      FactDescriptor('kittens.purred', type: const BoolType()),
    );
    expect(() => purr.emit(1), throwsA(isA<TypeMismatch>()));
    await p.flush();
    await settle();
    expect(errors, isEmpty, reason: 'nothing went to the host');
    expect(r.read('kittens.lamp'), isNull);
    expect(r.recent('kittens.purred'), isEmpty);
  });

  test('it watches another\'s state through its mirror', () async {
    final owner = r.participant(crew, vocabularies: [WordSet.open('studio')]);
    final program = owner.state(_Program.scene).define()..set('main');
    final p = await join();
    final seen = <String?>[];
    final sub = p.state(_Program.scene).watch().listen(seen.add);
    await settle();
    program.set('break');
    await settle();
    expect(seen, ['main', 'break']);
    await sub.cancel();
  });

  test('only a new participant is served, and once', () {
    final (_, srv) = RpcChannelTransport.memoryPair();
    final h = RpcPeerEndpoint(transport: srv);
    addTearDown(h.close);
    final fresh = r.participant(
      kittens,
      vocabularies: [WordSet.open('kittens')],
    );
    final s = fresh.serve(h);
    addTearDown(s.close);
    expect(() => fresh.serve(h), throwsStateError, reason: 'served already');
    final used = r.participant(crew, vocabularies: [WordSet.open('crew')]);
    used.defineState(StateDescriptor('crew.ready', type: const BoolType()));
    expect(() => used.serve(h), throwsStateError, reason: 'it did things here');
  });

  test('its access by default is the host\'s, told when it joins', () async {
    final p = await join(access: WordAccess(call: Callers.only(['user'])));
    expect(p.access.call?.toJson(), Callers.only(['user']).toJson());
    p.command(LampCommand.turn).define((_) {});
    await p.flush();
    expect(
      r.commandDescriptor('kittens.lamp.turn')!.callers.toJson(),
      Callers.only(['user']).toJson(),
    );
  });

  test('over an endpoint made elsewhere it is the same participant, and '
      'leaves the endpoint open', () async {
    final (c, srv) = RpcChannelTransport.memoryPair();
    final h = RpcPeerEndpoint(transport: srv);
    final s = r
        .participant(kittens, vocabularies: [WordSet.open('kittens')])
        .serve(h);
    h.start();
    final guest = RpcPeerEndpoint(transport: c)..start();
    final p = await RemoteParticipant.over(guest);
    final lamps = Lamps();
    p.attach({'lamps': lamps});
    await p.flush();
    final done = await r.call('kittens.lamp.turn', {'on': true}, by: crew);
    expect(done.ok, isTrue, reason: '$done');
    expect(lamps.lit, isTrue);
    await p.close();
    expect(identical(p.endpoint, guest), isTrue);
    s.close();
    await guest.close();
    await h.close();
  });

  test('explain and recent answer across a connection as in the host\'s '
      'process', () async {
    final owner = r.participant(crew, vocabularies: [WordSet.open('studio')]);
    owner.defineState(
      StateDescriptor(
        'studio.secret',
        type: const TextType(),
        readers: Callers.only(['user']),
      ),
    );
    owner.defineFact(
      FactDescriptor(
        'studio.whisper',
        type: const TextType(),
        readers: Callers.only(['user']),
      ),
    );
    final here = r.participant(kittens.child('here'));
    final there = await join();
    for (final p in <IParticipant>[here, there]) {
      final none = await p.explain('studio.nothing');
      expect((none.value, none.change), (null, null));
      expect(none.trail, isEmpty);
      await expectLater(
        p.explain('studio.secret'),
        throwsA(isA<NotPermitted>()),
      );
      expect(await p.recent('studio.whisper', 5), isEmpty);
      expect(await p.recent('studio.nothing', 5), isEmpty);
    }
  });

  test('a host gone is told as such, not as the wire\'s error', () async {
    final p = await join();
    session?.close();
    await host?.close();
    await settle();
    await expectLater(p.describe(), throwsA(isA<RegistryUnreachable>()));
  });

  test('a subscription naming more than the host takes is refused', () async {
    final (c, srv) = RpcChannelTransport.memoryPair();
    final h = RpcPeerEndpoint(transport: srv);
    final s = r.participant(kittens).serve(h, maxSubscription: 3);
    h.start();
    final connection = RpcClientConnection(
      transportFactory: (_) async => c,
      shouldReconnect: (_) => false,
    );
    final p = await RemoteParticipant.join(connection);
    final errors = [
      for (final name in ['a.x', 'a.y', 'a.z', 'a.w'])
        p.watch(name).listen((_) {}),
    ];
    await settle();
    expect(s.states, isEmpty, reason: "refused: it carries what it did before");
    for (final e in errors) {
      await e.cancel();
    }
    await p.close();
    await connection.dispose();
    s.close();
    await h.close();
  });

  test('its command past the deadline is timedOut, and its late end is '
      'recorded', () async {
    final p = await join();
    final ended = Completer<void>();
    p.defineCommand(
      CommandDescriptor(
        'kittens.slow',
        callers: Callers.only(['user']),
        deadline: const Duration(milliseconds: 100),
      ),
      (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        ended.complete();
        return null;
      },
    );
    await p.flush();
    final records = <CallRecord>[];
    r.calls.listen(records.add);
    expect(await r.call('kittens.slow', {}, by: crew), isA<CallTimedOut>());
    await ended.future;
    await settle();
    expect(
      [for (final c in records) (c.result.runtimeType, c.late)],
      [(CallTimedOut, false), (CallDone<Object?>, true)],
    );
  });

  test('a call that writes what it does not watch answers at once', () async {
    final studio = r.participant(crew, vocabularies: [WordSet.open('studio')]);
    final program = studio.defineState(
      StateDescriptor('studio.program', type: const TextType()),
    );
    studio.defineCommand(
      CommandDescriptor('studio.show', callers: Callers.only(['plugin'])),
      (c) => program.set('break', cause: c.causeFor(crew)),
    );
    final p = await join();
    final took = Stopwatch()..start();
    expect((await p.call('studio.show', {})).ok, isTrue);
    expect(
      took.elapsedMilliseconds,
      lessThan(500),
      reason: 'not waiting out reach for a tick it is never sent',
    );
  });

  test('a host of another protocol is refused, saying both versions', () {
    expect(() => checkProtocol(parlanceProtocol), returnsNormally);
    expect(
      () => checkProtocol(parlanceProtocol - 1),
      throwsA(
        isA<ProtocolMismatch>().having(
          (e) => '$e',
          'says',
          contains(
            'protocol ${parlanceProtocol - 1}, this participant '
            '$parlanceProtocol',
          ),
        ),
      ),
    );
    expect(() => checkProtocol(null), throwsA(isA<ProtocolMismatch>()));
  });

  test('a word it may not read holds back none of the words it watches '
      'after', () async {
    final owner = r.participant(crew, vocabularies: [WordSet.open('studio')]);
    owner
        .defineState(
          StateDescriptor(
            'studio.secret',
            type: const TextType(),
            readers: Callers.only(['user']),
          ),
        )
        .set('hush');
    owner.state(_Program.scene).define().set('main');
    final p = await join();
    final secret = p.watch('studio.secret').listen((_) {});
    await settle();
    final seen = <String?>[];
    final program = p.state(_Program.scene).watch().listen(seen.add);
    await settle();
    expect(seen, ['main']);
    expect(p.read('studio.secret'), isNull);
    expect(p.status('studio.secret'), const WordNotPermitted());
    await secret.cancel();
    await program.cancel();
  });

  test('a word it watches before it is there counts once it comes', () async {
    final p = await join();
    final sub = p.state(_Program.scene).watch().listen((_) {});
    await settle();
    expect(r.usesOf('studio.program'), isEmpty);
    final owner = r.participant(crew, vocabularies: [WordSet.open('studio')]);
    owner.state(_Program.scene).define().set('main');
    await settle();
    expect(r.usesOf('studio.program').single.listening, 1);
    await sub.cancel();
  });

  test('what it watches is its use of the word, while it watches', () async {
    final owner = r.participant(crew, vocabularies: [WordSet.open('studio')]);
    owner.state(_Program.scene).define().set('main');
    final p = await join();
    final sub = p.state(_Program.scene).watch().listen((_) {});
    await settle();
    final use = r.usesOf('studio.program').single;
    expect((use.by, use.listening), (kittens, 1));
    await sub.cancel();
    await settle();
    expect(r.usesOf('studio.program').single.listening, 0, reason: 'gone');
  });

  test('going, it withdraws its words', () async {
    final p = await join();
    p.attach({'lamps': Lamps()});
    await p.flush();
    expect(r.commandDescriptor('kittens.lamp.turn'), isNotNull);
    await p.close();
    expect(r.commandDescriptor('kittens.lamp.turn'), isNull);
    expect(r.stateDescriptor('kittens.lamp'), isNull);
  });
  test('its access by default goes with what it defines', () async {
    final p = await join(
      access: WordAccess(read: Callers.only(['plugin/kittens'])),
    );
    p.state(Lamp.on).define();
    await p.flush();
    expect(r.stateDescriptor('kittens.lamp')!.readers!.rules.keys, {
      'plugin/kittens',
    });
  });

  test('a connection that gives up is told to its errors', () async {
    final p = await join();
    final errors = <ParticipantError>[];
    p.errors.listen(errors.add);
    final gone = connection!.state.firstWhere(
      (s) => s is RpcClientDisconnected,
    );
    session!.close();
    await host!.close();
    await gone;
    await settle();
    expect(errors.map((e) => (e.op['op'], e.code)), [('join', 'lost')]);
  });

  test('away, it keeps the last facts it said, as many as it may, and tells '
      'how many went', () async {
    final sessions = <RemoteSession>[];
    final hosts = <RpcPeerEndpoint>[];
    final connection = RpcClientConnection(
      transportFactory: (_) async {
        final (c, s) = RpcChannelTransport.memoryPair();
        final h = RpcPeerEndpoint(transport: s);
        final session = r
            .participant(kittens, vocabularies: [WordSet.open('kittens')])
            .serve(h);
        h.start();
        sessions.add(session);
        hosts.add(h);
        return c;
      },
      backoff: const RpcFixedBackoff(Duration(milliseconds: 10)),
    );
    final p = await RemoteParticipant.join(connection, keepAway: 2);
    final errors = <ParticipantError>[];
    p.errors.listen(errors.add);
    final lamps = Lamps();
    p.attach({'lamps': lamps});
    await p.flush();

    final offline = connection.state.firstWhere((s) => s is! RpcClientOnline);
    sessions.last.close();
    await hosts.last.close();
    await offline;
    lamps
      ..purr()
      ..lit = true
      ..purr()
      ..purr();

    final back = DateTime.now().add(const Duration(seconds: 5));
    while (r.recent('kittens.purred').length < 2 &&
        DateTime.now().isBefore(back)) {
      await settle();
    }
    expect(r.recent('kittens.purred').map((f) => f.payload), [
      {'on': true},
      {'on': true},
    ], reason: 'the last two');
    expect(errors.single.code, 'dropped');
    expect(errors.single.message, contains('1 facts'));

    await p.close();
    await connection.dispose();
    for (final s in sessions) {
      s.close();
    }
    for (final h in hosts) {
      await h.close();
    }
  });

  test('it outlives a lost connection: the new session gets its words as '
      'they stand, and then what it said while away', () async {
    final sessions = <RemoteSession>[];
    final hosts = <RpcPeerEndpoint>[];
    final connection = RpcClientConnection(
      transportFactory: (_) async {
        final (c, s) = RpcChannelTransport.memoryPair();
        final h = RpcPeerEndpoint(transport: s);
        final session = r
            .participant(kittens, vocabularies: [WordSet.open('kittens')])
            .serve(h);
        h.start();
        sessions.add(session);
        hosts.add(h);
        return c;
      },
      backoff: const RpcFixedBackoff(Duration(milliseconds: 10)),
    );
    final p = await RemoteParticipant.join(connection);
    final lamps = Lamps();
    p.attach({'lamps': lamps});
    await p.flush();
    expect(r.read('kittens.lamp'), false);

    // The connection drops: the host ends the session, its words go.
    final offline = connection.state.firstWhere((s) => s is! RpcClientOnline);
    sessions.last.close();
    await hosts.last.close();
    await offline;
    expect(r.commandDescriptor('kittens.lamp.turn'), isNull);

    // Away, it writes and says.
    lamps
      ..lit = true
      ..sync()
      ..purr();

    final back = DateTime.now().add(const Duration(seconds: 5));
    while (r.read('kittens.lamp') != true && DateTime.now().isBefore(back)) {
      await settle();
    }
    expect(sessions, hasLength(2));
    expect(r.read('kittens.lamp'), true, reason: 'its value as it stands');
    expect(r.recent('kittens.purred').map((f) => f.payload), [
      {'on': true},
    ], reason: 'what it said away');
    final served = await r.call('kittens.lamp.turn', {'on': false}, by: crew);
    expect(served.ok, isTrue, reason: '$served');
    expect(lamps.lit, isFalse, reason: 'served over the new connection');

    await p.close();
    await connection.dispose();
    for (final s in sessions) {
      s.close();
    }
    for (final h in hosts) {
      await h.close();
    }
  });
}

enum _Program<T> implements IStateWord<T> {
  scene<String>('studio.program');

  const _Program(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const Plain(TextType()) as Shape<T>;
  @override
  String? get key => null;
}
