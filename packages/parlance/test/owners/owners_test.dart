import 'dart:async';

import 'package:parlance/owners.dart';
import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

const me = Principal('host');

enum Level<T> implements IStateWord<T> {
  of<num>('test.level', Plain(NumType()));

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
  final Map<String, num> dials = {'a': 1, 'b': 2};
  late final StateWriterOf<num> _level;
  late final TrackedKind _kind;
  var synced = 0;

  @override
  void define(IParticipant p) {
    _kind = trackKind('dial', () => [for (final d in dials.keys) EntityRef(d)]);
    _level = keep(p.state(Level.of).define());
  }

  @override
  void sync() {
    synced++;
    for (final gone in _kind.sync()) {
      _level.remove(key: gone);
    }
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
  void define(IParticipant p) => listen(turns, heard.add);
}

final class Other extends Owner {
  @override
  void define(IParticipant p) {
    keep(p.state(_Flag.on).define());
  }
}

/// Dials that say what they own and use.
final class Told extends Dials {
  @override
  Iterable<IWord> get words => Level.values;

  @override
  Iterable<Use> get uses => const [Use.optional(_Flag.on)];
}

/// One that needs the dials' level, and can do without the flag.
final class Needy extends Owner {
  @override
  Iterable<Use> get uses => const [
    Use.required(Level.of),
    Use.optional(_Flag.on),
  ];

  @override
  void define(IParticipant p) {}
}

enum _Flag<T> implements IStateWord<T> {
  on<bool>('test.on', Plain(BoolType()));

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

  /// The module's participant, as `main` makes it.
  IParticipant module([Set<String> namespaces = const {'test'}]) =>
      r.participant(me, namespaces: namespaces);

  test('owners define, sync as one tick, and withdraw their words', () async {
    final ticks = <Tick>[];
    r.ticks.listen(ticks.add);
    final dials = Dials();
    final owners = Owners(module(), {'dials': dials, 'other': Other()});
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
    Owners(module(), {'dials': dials});
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
    Owners(module(), {'other': o});
    expect(() => o.attach(r.participant(me)), throwsStateError);
    final h = Handles()..dispose();
    expect(() => h.keep(r.state(_Flag.on).define(by: me)), throwsStateError);
    expect(r.stateDescriptor('test.on'), isNotNull, reason: 'o still has it');
  });

  test('an owner defines only in the namespaces main gave its participant', () {
    expect(
      () => Owners(module({'test.level'}), {'other': Other()}),
      throwsA(isA<NotPermitted>()),
    );
    expect(r.stateDescriptor('test.on'), isNull);
  });

  test('the participant main made says who reads the owners\' words', () {
    Owners(
      r.participant(
        me,
        namespaces: {'test'},
        access: WordAccess(read: Callers.only(['host'])),
      ),
      {'dials': Dials()},
    );
    expect(r.stateDescriptor('test.level')!.readers!.rules.keys, {'host'});
  });

  test('going, the owners leave the participant to main', () {
    final p = module();
    Owners(p, {'other': Other()}).dispose();
    expect(r.stateDescriptor('test.on'), isNull);
    expect(p.status('test.on'), const WordMissing());
    Owners(p, {'other': Other()});
    expect(r.stateDescriptor('test.on'), isNotNull, reason: 'p still speaks');
  });

  test('each owner speaks as its part, named by main: what it writes and '
      'its calls tell which owner it was', () async {
    final p = module();
    Owners(p, {'dials': Dials(), 'other': Other()});
    expect(r.lastChange('test.level', key: 'a')!.cause.by, me.child('dials'));
    expect(r.lastChange('test.on'), isNull);
    expect(me.child('dials').selector, 'host:dials');
  });

  test('an owner listens while attached, and stops when it goes', () async {
    final turns = StreamController<num>.broadcast();
    final knob = Knob(turns.stream);
    final owners = Owners(module(), {'knob': knob});
    turns.add(1);
    await pumpEventQueue();
    expect(knob.heard, [1]);
    owners.dispose();
    await pumpEventQueue();
    expect(turns.hasListener, isFalse);
    await turns.close();
  });

  test('a required word not there stops main, told by part and word; an '
      'optional one does not', () async {
    final needy = Owners(module({'needy'}), {'needy': Needy()});
    await expectLater(
      needy.checkUses(),
      throwsA(
        isA<UnmetUses>().having(
          (e) => e.message,
          'message',
          'host:needy needs test.level: missing',
        ),
      ),
    );
    Owners(module(), {'dials': Dials()});
    await needy.checkUses();
  });

  test('a required word withheld from the part is not met', () async {
    Owners(
      r.participant(
        const Principal('dials'),
        namespaces: {'test'},
        access: WordAccess(read: Callers.only(['dials'])),
      ),
      {'dials': Dials()},
    );
    final needy = Owners(module({'needy'}), {'needy': Needy()});
    await expectLater(
      needy.checkUses(),
      throwsA(
        isA<UnmetUses>().having(
          (e) => e.unmet.single.status,
          'status',
          const WordNotPermitted(),
        ),
      ),
    );
  });

  test('an owner says what it owns and uses; describe tells it as its '
      'part\'s, until it goes', () async {
    final changes = <CatalogChange>[];
    r.catalogChanges.listen(changes.add);
    final owners = Owners(module(), {'dials': Told()});
    final part = me.child('dials');
    expect(r.declarations[part]!.owns, {'test.level'});
    expect(r.describe()['declared'], {
      part.selector: {
        'owns': ['test.level'],
        'uses': {'test.on': 'optional'},
      },
    });
    owners.dispose();
    await pumpEventQueue();
    expect(r.declarations, isEmpty);
    expect(changes.whereType<DeclarationChanged>().map((c) => c.by), [
      part,
      part,
    ]);
  });

  test('a word it lists outside its namespaces is refused before it '
      'defines anything', () {
    expect(
      () => Owners(module({'other'}), {'dials': Told()}),
      throwsA(isA<NotPermitted>()),
    );
    expect(r.declarations, isEmpty);
    expect(r.stateDescriptor('test.level'), isNull);
  });
}
