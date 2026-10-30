import 'dart:async';

import 'package:parlance/schema.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/app.dart' show ServeAcross;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

part 'owners_test.g.dart';

const me = Principal('host');

/// Dials and their levels: one keyed state, the choices of its keys.
@Vocabulary('test')
abstract class Test {
  @StateWord('level', keyOf: 'dial')
  num get level;
}

/// A flag.
@Vocabulary('flag')
abstract class Flag {
  @StateWord('on')
  bool get on;
}

/// No words: an owner that only listens has a vocabulary too.
@Vocabulary('knob')
abstract class KnobWords {}

/// Dials and their levels, synced again when [moved] says their model
/// moved.
final class Dials extends TestOwnerBase {
  Dials({Stream<void>? moved}) {
    choices(
      name: TestChoices.dial,
      list: () => [for (final d in dials.keys) Choice(d)],
    );
    follow(pull: _pull, on: moved);
  }

  final Map<String, num> dials = {'a': 1, 'b': 2};
  var synced = 0;

  void _pull() {
    synced++;
    for (final MapEntry(:key, :value) in dials.entries) {
      level.set(key, value);
    }
  }
}

/// What turns come from on their own: a stream it listens to.
final class Knob extends KnobWordsOwnerBase {
  Knob(Stream<num> turns) {
    listen(on: turns, onData: heard.add);
  }

  final List<num> heard = [];
}

/// The flag, defined and never set.
final class Other extends FlagOwnerBase {}

/// The flag, written from its model whenever [moved] says it moved.
final class Flagged extends FlagOwnerBase {
  Flagged() {
    follow(pull: () => on.set(lit), on: moved.stream);
  }

  bool lit = false;
  final StreamController<void> moved = StreamController.broadcast();
}

void main() {
  late Registry r;
  setUp(() => r = Registry(onError: (e, st) => throw e));
  tearDown(() => r.dispose());

  /// The module's participant of [owners], as `main` makes it.
  IParticipant module([List<IOwner> owners = const []]) =>
      r.participant(me, owners: owners);

  test('owners define, sync as one tick, and withdraw their words', () async {
    final ticks = <Tick>[];
    r.ticks.listen(ticks.add);
    final owners = module([Dials(), Other()]);
    await pumpEventQueue();
    expect(ticks, hasLength(1));
    expect(r.readAll('test.level'), {'a': 1, 'b': 2});
    owners.dispose();
    expect(r.stateDescriptor('test.level'), isNull);
    expect(r.stateDescriptor('flag.on'), isNull);
    expect(r.hasChoices('dial'), isFalse);
  });

  test(
    'choices announce a change, and what went goes of the keyed state',
    () async {
      final dials = Dials();
      final p = module([dials]);
      final changes = <CatalogChange>[];
      r.catalogChanges.listen(changes.add);
      dials.dials.remove('a');
      dials.dials['c'] = 3;
      p.sync();
      await pumpEventQueue();
      expect(changes.whereType<ChoicesChanged>().map((c) => c.name), ['dial']);
      expect(r.readAll('test.level'), {'b': 2, 'c': 3});
      changes.clear();
      p.sync();
      await pumpEventQueue();
      expect(changes, isEmpty, reason: 'nothing changed');
    },
  );

  test('an owner attaches once', () {
    final o = Other();
    module([o]);
    expect(
      () => r.participant(const Principal('elsewhere'), owners: [o]),
      throwsStateError,
    );
    expect(r.stateDescriptor('flag.on'), isNotNull, reason: 'o still has it');
  });

  test('the participant main made says who reads the owners\' words', () {
    r.participant(
      me,
      access: WordAccess(readers: Callers.only(['host'])),
      owners: [Dials()],
    );
    expect(r.stateDescriptor('test.level')!.readers!.rules.keys, {'host'});
  });

  test('going, a participant takes its owners with it, and their '
      'vocabularies are free again', () {
    final p = module([Other()]);
    p.dispose();
    expect(r.stateDescriptor('flag.on'), isNull);
    module([Other()]);
    expect(r.stateDescriptor('flag.on'), isNotNull, reason: 'flag is free');
  });

  test('an owner speaks as the owner named by its vocabulary', () async {
    module([Dials(), Other()]);
    expect(r.lastChange('test.level', key: 'a')!.cause.by, me.ofOwner('test'));
    expect(r.lastChange('flag.on'), isNull);
    expect(me.ofOwner('test').selector, 'host@test');
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
    final moved = StreamController<void>.broadcast();
    final dials = Dials(moved: moved.stream);
    final flag = Flagged();
    module([dials, flag]);
    expect(dials.synced, 1);
    final ticks = <Tick>[];
    r.ticks.listen(ticks.add);
    dials.dials['a'] = 5;
    moved
      ..add(null)
      ..add(null);
    flag.lit = true;
    flag.moved.add(null);
    await pumpEventQueue();
    expect(dials.synced, 2, reason: 'once for the turn');
    expect(ticks, hasLength(1), reason: 'one tick for both');
    expect(r.read('test.level', key: 'a'), 5);
    expect(r.read('flag.on'), isTrue);
  });

  test('a scope is a participant: going, it leaves nothing of itself, its '
      'words, values and choices, and others see them missing', () async {
    final outsider = r.participant(const Principal('outsider'));
    final statuses = <WordStatus>[];
    outsider.statusChanges('test.level').listen(statuses.add);
    final dials = Dials();
    final flag = Flagged()..lit = true;
    final p = module([dials, flag]);
    await pumpEventQueue();
    p.dispose();
    await pumpEventQueue();
    expect(r.stateDescriptor('test.level'), isNull);
    expect(r.stateDescriptor('flag.on'), isNull);
    expect(r.readAll('test.level'), isEmpty);
    expect(r.hasChoices('dial'), isFalse);
    expect(statuses.last, const WordMissing());
    // What it writes after it went (code still running then) is not
    // written, and throws nothing.
    dials.level.set('a', 9);
    expect(r.readAll('test.level'), isEmpty, reason: 'withdrawn');
    module([Dials()]);
    expect(r.read('test.level', key: 'a'), 1, reason: 'the next session');
  });
}
