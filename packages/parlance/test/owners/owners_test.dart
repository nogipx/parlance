import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:parlance/app.dart' show ServeAcross;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/owner.dart' show Owner;
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/src/registry/words.dart' show TypedRegistry;

const me = Principal('host');

enum Level<T> implements IStateWord<T> {
  of<num>('test.level', PlainShape(NumType()));

  const Level(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => 'dial';
}

/// Dials and their levels: one keyed state, a kind it keeps.
final class Dials extends Owner {
  Dials() : super(vocabulary: 'test');

  final Map<String, num> dials = {'a': 1, 'b': 2};
  late final IStateWriterOf<num> _level;
  final Set<String> _written = {};
  var synced = 0;

  @override
  void define(IRawParticipant p) {
    choices(name: 'dial', list: () => [for (final d in dials.keys) Choice(d)]);
    _level = keep(GeneratedWords(p).state(Level.of).define());
  }

  @override
  void sync() {
    synced++;
    for (final gone in _written.difference(dials.keys.toSet())) {
      _level.remove(key: gone);
    }
    _written
      ..clear()
      ..addAll(dials.keys);
    for (final MapEntry(:key, :value) in dials.entries) {
      _level.set(value, key: key);
    }
  }
}

/// What turns come from on their own: a stream it listens to.
final class Knob extends Owner {
  Knob(this.turns);
  final Stream<num> turns;
  final List<num> heard = [];

  @override
  void define(IRawParticipant p) => listen(on: turns, onData: heard.add);
}

final class Other extends Owner {
  @override
  void define(IRawParticipant p) {
    keep(GeneratedWords(p).state(_Flag.on).define());
  }
}

/// Dials that say when their model changed.
final class Watched extends Dials {
  final StreamController<void> moved = StreamController.broadcast();

  @override
  Stream<void> get changes => moved.stream;
}

/// One more, of another part, writing the flag from its model.
final class Flagged extends Owner {
  bool on = false;
  final StreamController<void> moved = StreamController.broadcast();
  late final IStateWriterOf<bool> _on;

  @override
  Stream<void> get changes => moved.stream;

  @override
  void define(IRawParticipant p) =>
      _on = keep(GeneratedWords(p).state(_Flag.on).define());

  @override
  void sync() => _on.set(on);
}

enum _Flag<T> implements IStateWord<T> {
  on<bool>('test.on', PlainShape(BoolType()));

  const _Flag(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

void main() {
  late Registry r;
  setUp(() => r = Registry(onError: (e, st) => throw e));
  tearDown(() => r.dispose());

  /// The module's participant of [owners], as `main` makes it.
  IParticipant module([
    List<IOwner> owners = const [],
    Set<String> names = const {'test'},
  ]) => r.participant(
    me,
    owners: owners,
    vocabularies: [for (final n in names) WordSet.open(n)],
  );

  test('owners define, sync as one tick, and withdraw their words', () async {
    final ticks = <Tick>[];
    r.ticks.listen(ticks.add);
    final dials = Dials();
    final owners = module([dials, Other()]);
    await pumpEventQueue();
    expect(ticks, hasLength(1));
    expect(r.state(Level.of).readAll(), {'a': 1, 'b': 2});
    owners.dispose();
    expect(r.stateDescriptor('test.level'), isNull);
    expect(r.stateDescriptor('test.on'), isNull);
    expect(r.hasKind('dial'), isFalse);
  });

  test('a tracked kind announces a change and names what went', () async {
    final dials = Dials();
    module([dials]);
    final changes = <CatalogChange>[];
    r.catalogChanges.listen(changes.add);
    dials.dials.remove('a');
    dials.dials['c'] = 3;
    r.batch(dials.sync);
    await pumpEventQueue();
    expect(changes.whereType<KindChanged>().map((c) => c.kind), ['dial']);
    expect(r.state(Level.of).readAll(), {'b': 2, 'c': 3});
    changes.clear();
    r.batch(dials.sync);
    await pumpEventQueue();
    expect(changes, isEmpty, reason: 'nothing changed');
  });

  test('an owner attaches once; handles withdrawn take no more', () {
    final o = Other();
    module([o]);
    expect(
      () => r.participant(
        const Principal('elsewhere'),
        owners: [o],
        vocabularies: [WordSet.open('elsewhere')],
      ),
      throwsStateError,
    );
    final h = Handles()..dispose();
    expect(() => h.keep(r.state(_Flag.on).define(by: me)), throwsStateError);
    expect(r.stateDescriptor('test.on'), isNotNull, reason: 'o still has it');
  });

  test(
    'an owner defines only in the vocabularies main gave its participant',
    () {
      expect(() => module([Other()], {'dials'}), throwsA(isA<NotPermitted>()));
      expect(r.stateDescriptor('test.on'), isNull);
    },
  );

  test('the participant main made says who reads the owners\' words', () {
    r.participant(
      me,
      vocabularies: [WordSet.open('test')],
      access: WordAccess(readers: Callers.only(['host'])),
      owners: [Dials()],
    );
    expect(r.stateDescriptor('test.level')!.readers!.rules.keys, {'host'});
  });

  test('going, a participant takes its owners with it, and its vocabulary '
      'is free again', () {
    final p = module([Other()]);
    p.dispose();
    expect(r.stateDescriptor('test.on'), isNull);
    module([Other()]);
    expect(r.stateDescriptor('test.on'), isNotNull, reason: 'test is free');
  });

  test('an owner speaks as the part named by its vocabulary; one of no '
      'words as the participant', () async {
    module([Dials(), Other()]);
    expect(r.lastChange('test.level', key: 'a')!.cause.by, me.child('test'));
    expect(r.lastChange('test.on'), isNull);
    expect(me.child('test').selector, 'host@test');
  });

  test('a participant of owners here is not served across a connection', () {
    final (_, h) = RpcChannelTransport.memoryPair();
    expect(
      () => module([Dials()]).serve(RpcPeerEndpoint(transport: h)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('has its owners at the other end'),
        ),
      ),
    );
  });

  test('two owners of one vocabulary are refused', () {
    expect(
      () => module([Dials(), Dials()]),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('one vocabulary, one owner'),
        ),
      ),
    );
  });

  test('an owner listens while attached, and stops when it goes', () async {
    final turns = StreamController<num>.broadcast();
    final knob = Knob(turns.stream);
    final owners = module([knob]);
    turns.add(1);
    await pumpEventQueue();
    expect(knob.heard, [1]);
    owners.dispose();
    await pumpEventQueue();
    expect(turns.hasListener, isFalse);
    await turns.close();
  });

  test('an owner that says when its model moved is synced on its own: '
      'what one turn told, once and as one tick for the group', () async {
    final dials = Watched();
    final flag = Flagged();
    module([dials, flag]);
    expect(dials.synced, 1);
    final ticks = <Tick>[];
    r.ticks.listen(ticks.add);
    dials.dials['a'] = 5;
    dials.moved
      ..add(null)
      ..add(null);
    flag.on = true;
    flag.moved.add(null);
    await pumpEventQueue();
    expect(dials.synced, 2, reason: 'once for the turn');
    expect(ticks, hasLength(1), reason: 'one tick for both');
    expect(r.state(Level.of).read(key: 'a'), 5);
    expect(r.state(_Flag.on).read(), isTrue);
  });

  test('a scope is a participant: going, it leaves nothing of itself, its '
      'words, values and kinds, and others see them missing', () async {
    final outsider = r.participant(const Principal('outsider'));
    final statuses = <WordStatus>[];
    outsider.statusChanges('test.level').listen(statuses.add);
    final dials = Dials();
    final p = module([dials]);
    final part = p.raw.child('dials');
    GeneratedWords(part).state(_Flag.on).define().set(true);
    await pumpEventQueue();
    p.dispose();
    await pumpEventQueue();
    expect(r.stateDescriptor('test.level'), isNull);
    expect(r.stateDescriptor('test.on'), isNull, reason: 'the part went');
    expect(r.state(Level.of).readAll(), isEmpty);
    expect(r.hasKind('dial'), isFalse);
    expect(statuses.last, const WordMissing());
    // What it writes after it went (code still running then) is not
    // written, and throws nothing.
    dials.dials['a'] = 9;
    dials.sync();
    expect(r.state(Level.of).readAll(), isEmpty, reason: 'withdrawn');
    module([Dials()]);
    expect(r.state(Level.of).read(key: 'a'), 1, reason: 'the next session');
  });
}
