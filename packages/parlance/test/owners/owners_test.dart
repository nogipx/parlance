import 'dart:async';

import 'package:parlance/owners.dart';
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
  void define(Registry r) {
    _kind = trackKind('dial', () => [for (final d in dials.keys) EntityRef(d)]);
    _level = keep(r.state(Level.of).define(by: me));
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
  void define(Registry r) => listen(turns, heard.add);
}

final class Other extends Owner {
  @override
  void define(Registry r) {
    keep(r.state(_Flag.on).define(by: me));
  }
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

  test('owners define, sync as one tick, and withdraw their words', () async {
    final ticks = <Tick>[];
    r.ticks.listen(ticks.add);
    final dials = Dials();
    final owners = Owners(r, [dials, Other()]);
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
    Owners(r, [dials]);
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
    Owners(r, [o]);
    expect(() => o.attach(r), throwsStateError);
    final h = Handles()..dispose();
    expect(() => h.keep(r.state(_Flag.on).define(by: me)), throwsStateError);
    expect(r.stateDescriptor('test.on'), isNotNull, reason: 'o still has it');
  });

  test('an owner listens while attached, and stops when it goes', () async {
    final turns = StreamController<num>.broadcast();
    final knob = Knob(turns.stream);
    final owners = Owners(r, [knob]);
    turns.add(1);
    await pumpEventQueue();
    expect(knob.heard, [1]);
    owners.dispose();
    await pumpEventQueue();
    expect(turns.hasListener, isFalse);
    await turns.close();
  });
}
