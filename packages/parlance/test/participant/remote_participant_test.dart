import 'dart:async';

import 'package:parlance/owners.dart';
import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
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
  Principal get who => kittens;
  @override
  Set<String> get namespaces => const {'kittens'};

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
}

void main() {
  late Registry r;
  late RegistryResponder session;
  late RpcPeerEndpoint host;
  late RpcPeerEndpoint guest;

  Future<RemoteParticipant> join({
    Set<String> namespaces = const {'kittens'},
    SessionRights rights = SessionRights.none,
  }) {
    final (c, s) = RpcChannelTransport.memoryPair();
    host = RpcPeerEndpoint(transport: s);
    session = RegistryResponder(
      host,
      r,
      principal: kittens,
      namespaces: namespaces,
      rights: rights,
    );
    host
      ..registerServiceContract(session)
      ..start();
    guest = RpcPeerEndpoint(transport: c)..start();
    return RemoteParticipant.connect(guest);
  }

  setUp(() => r = Registry(overriders: {'user'}));
  tearDown(() async {
    session.close();
    await guest.close();
    await host.close();
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
    lamps
      ..attach(p)
      ..sync();
    await p.flush();
    expect(r.read('kittens.lamp'), false);

    final crewSide = r.participant(crew);
    final done = await crewSide.command(LampCommand.turn).call((on: true));
    expect(done.ok, isTrue, reason: '$done');
    expect(r.read('kittens.lamp'), true);
    final change = r.lastChange('kittens.lamp')!;
    expect(change.cause.by, kittens);
    expect(change.cause.parent, isNotNull, reason: 'it follows from the call');
    final purr = r.recent('kittens.purred').single;
    expect(purr.cause.parent, change.cause.parent);
    expect(p.state(Lamp.on).read(), true, reason: 'its own, as it wrote it');
    expect(crewSide.status('kittens.lamp.turn'), const WordReady());
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
      rights: SessionRights(
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

  test('its guard is asked in its turn, before the hooks', () async {
    final p = await join();
    var served = 0;
    p
        .command(LampCommand.turn)
        .define(
          (_) => served++,
          callers: Callers.only(['user']),
          interceptable: true,
        );
    p.addGuard(
      'night',
      (c) => c.params['on'] == true ? 'the kittens sleep' : null,
    );
    await p.flush();
    var hooked = 0;
    r.addBefore(
      'kittens.lamp.turn',
      'h',
      (_, _) async => hooked++,
      timeout: const Duration(seconds: 1),
    );

    final denied = await r.call('kittens.lamp.turn', {'on': true}, by: crew);
    expect(denied, isA<CallRefused>());
    expect((denied as CallRefused).code, Refusal.denied);
    expect(denied.reason, 'the kittens sleep');
    expect(denied.guard, 'plugin:kittens/night');
    expect((hooked, served), (0, 0), reason: 'denied before the hooks');
    expect(
      (await r.call('kittens.lamp.turn', {'on': false}, by: crew)).ok,
      isTrue,
    );
    expect((hooked, served), (1, 1));
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
      rights: SessionRights(
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

  test('it watches another\'s state through its mirror', () async {
    final owner = r.participant(crew, namespaces: {'studio'});
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

  test('going, it withdraws its words', () async {
    final p = await join();
    Lamps().attach(p);
    await p.flush();
    expect(r.commandDescriptor('kittens.lamp.turn'), isNotNull);
    await p.close();
    expect(r.commandDescriptor('kittens.lamp.turn'), isNull);
    expect(r.stateDescriptor('kittens.lamp'), isNull);
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
