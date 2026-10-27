import 'package:parlance/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  late Fixture f;
  late List<Tick> ticks;

  setUp(() {
    f = Fixture();
    ticks = [];
    f.r.ticks.listen(ticks.add);
  });
  tearDown(() => f.r.dispose());

  test(
    'a write is a tick of its own; an unchanged write is no change',
    () async {
      f.muted.set(true);
      f.muted.set(true);
      f.muted.set(false);
      await pumpEventQueue();
      expect(ticks, hasLength(2));
      expect(ticks[0].changes.single.value, true);
      expect(ticks[1].changes.single.previous, true);
      expect(ticks[1].from, ticks[0].to + 1);
      expect(f.r.read('audio.muted'), false);
    },
  );

  test('a batch commits once; inside it reads see its own writes', () async {
    Object? seenInside;
    Object? seenOutside;
    f.r.batch(() {
      f.program.set('main');
      f.muted.set(true);
      seenInside = f.r.read('audio.muted');
      seenOutside = f.r.has('audio.muted');
    });
    await pumpEventQueue();
    expect(seenInside, true);
    expect(seenOutside, isFalse, reason: 'not committed yet');
    expect(ticks.single.changes.map((c) => c.state), [
      'studio.program',
      'audio.muted',
    ]);
  });

  test('batches nest; the outermost commits', () async {
    f.r.batch(() {
      f.muted.set(true);
      f.r.batch(() => f.program.set('main'));
      expect(f.r.has('studio.program'), isFalse);
    });
    await pumpEventQueue();
    expect(ticks, hasLength(1));
  });

  test('an async batch is refused', () {
    expect(() => f.r.batch(() async {}), throwsArgumentError);
  });

  test('values are checked, keyed states want keys', () {
    expect(() => f.program.set('nowhere'), throwsA(isA<TypeMismatch>()));
    expect(() => f.gain.set(0), throwsArgumentError);
    expect(() => f.muted.set(true, key: 'x'), throwsArgumentError);
    f.gain.set(-3, key: 'mic');
    f.gain.set(-9, key: 'music');
    expect(f.r.readAll('audio.gain'), {'mic': -3, 'music': -9});
  });

  test('removing a key is a change', () async {
    f.gain.set(-3, key: 'mic');
    f.gain.remove(key: 'mic');
    f.gain.remove(key: 'mic');
    await pumpEventQueue();
    expect(ticks.last.changes.single.removed, isTrue);
    expect(ticks, hasLength(2));
    expect(f.r.has('audio.gain', key: 'mic'), isFalse);
  });

  test('watch gives the value now, then each change', () async {
    f.muted.set(true);
    final seen = <Object?>[];
    final sub = f.r.watch('audio.muted').listen(seen.add);
    await pumpEventQueue();
    f.muted.set(false);
    f.program.set('main');
    await pumpEventQueue();
    expect(seen, [true, false]);
    await sub.cancel();
  });

  test(
    'a name is defined once; a disposed state takes its values along',
    () async {
      expect(
        () => f.r.defineState(
          StateDescriptor('audio.muted', type: const BoolType()),
          by: owner,
        ),
        throwsStateError,
      );
      final removed = <CatalogChange>[];
      f.r.catalogChanges.listen(removed.add);
      f.gain.set(1, key: 'mic');
      f.gain.set(2, key: 'music');
      await pumpEventQueue();
      ticks.clear();
      f.gain.dispose();
      await pumpEventQueue();
      expect(ticks.single.changes.every((c) => c.removed), isTrue);
      expect(ticks.single.changes, hasLength(2));
      expect(f.r.stateDescriptor('audio.gain'), isNull);
      expect(removed.single, isA<DescriptorRemoved>());
      expect(() => f.gain.set(1, key: 'mic'), throwsStateError);
    },
  );

  test('a write inside a handler has the call as its parent', () async {
    final r = await f.r.call('audio.mute', {'on': true}, by: user, id: 'c1');
    expect(r.ok, isTrue);
    await pumpEventQueue();
    final c = ticks.single.changes.single;
    expect(c.cause.parent, 'c1');
    expect(c.cause.by, owner);
  });

  test('describeFor tells what a principal may call, and what cannot run', () {
    final d = f.r.describeFor(viewer);
    expect(d['descriptors'], f.r.describe()['descriptors']);
    final access = d['access'] as Map;
    expect(access['studio.show'], isIn(['allow', 'warn', 'deny']));
    expect(access['audio.gain.set'], 'deny');
    expect(d['unavailable'], isA<Map<String, Object?>>());
    expect(d.containsKey('protocol'), isFalse, reason: "remote's to say");
  });

  test('explain and call records go to JSON and back', () async {
    await f.r.call('audio.mute', {'on': true}, by: user, id: 'c1');
    await pumpEventQueue();
    final e = f.r.explain('audio.muted');
    expect(e.trail.single.id, 'c1');
    final back = Explanation.fromJson(e.toJson());
    expect(back.toJson(), e.toJson());
    expect(back.trail.single.cause.by, user);
    expect(back.change?.seq, e.change?.seq);
  });

  test('describe lists the catalog and the kinds', () {
    f.r.defineState(
      StateDescriptor(
        'studio.secret',
        type: const TextType(),
        readers: const Callers({'agent': Access.deny, '*': Access.allow}),
      ),
      by: owner,
    );
    expect(f.r.mayRead(agent, 'studio.secret'), isFalse);
    expect(f.r.mayRead(user, 'studio.secret'), isTrue);
    expect(f.r.describeFor(agent)['unreadable'], ['studio.secret']);
    expect(f.r.describeFor(user).containsKey('unreadable'), isFalse);
    final d = f.r.describe();
    expect(d['epoch'], f.r.epoch);
    final names = [
      for (final x in d['descriptors'] as List) (x as Map)['name'],
    ];
    expect(names, containsAll(['studio.program', 'audio.mute']));
    final back = [
      for (final x in d['descriptors'] as List) Descriptor.fromJson(x).toJson(),
    ];
    expect(back, d['descriptors']);
  });
}
