import 'dart:async';

import 'package:parlance/core.dart';
import 'package:test/test.dart';

/// The core (SPEC §21): local states, facts, commands and the hub.
void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('LocalState', () {
    test('one writer at a time; another may claim after it is released', () {
      final state = LocalState<int>();
      final w = state.claim();
      expect(state.claim, throwsStateError);
      w.dispose();
      expect(() => w.set(1), throwsStateError);
      expect(state.claim, returnsNormally);
    });

    test('a write commits at once outside a batch', () {
      final state = LocalState<int>();
      state.claim().set(1);
      expect(state.value, 1);
      expect(state.has, isTrue);
    });

    test('watch gives the value now, then every change', () async {
      final state = LocalState<int>();
      final w = state.claim()..set(1);
      final seen = <int?>[];
      final sub = state.watch().listen(seen.add);
      w
        ..set(2)
        ..remove();
      await settle();
      expect(seen, [1, 2, null]);
      await sub.cancel();
    });

    test('an equal value commits nothing', () async {
      final hub = LocalHub();
      final state = LocalState<List<int>>(
        hub: hub,
        equals: (a, b) => a.length == b.length,
      );
      final w = state.claim()..set([1]);
      final seq = hub.seq;
      w.set([2]);
      expect(hub.seq, seq);
      expect(state.value, [1]);
    });

    test('close drops what waits in a batch and refuses writers', () {
      final hub = LocalHub();
      final state = LocalState<int>(hub: hub);
      final w = state.claim();
      hub.batch(() {
        w.set(1);
        state.close();
      });
      expect(state.has, isFalse);
      expect(hub.seq, 0);
      expect(state.claim, throwsStateError);
    });
  });

  group('LocalKeyedState', () {
    test('a value per key; removing an absent key commits nothing', () {
      final hub = LocalHub();
      final state = LocalKeyedState<String, int>(hub: hub);
      final w = state.claim()
        ..set('a', 1)
        ..set('b', 2)
        ..remove('c');
      expect(state.values, {'a': 1, 'b': 2});
      expect(hub.seq, 2);
      w.remove('a');
      expect(state.has('a'), isFalse);
    });

    test('watch follows one key', () async {
      final state = LocalKeyedState<String, int>();
      final w = state.claim();
      final seen = <int?>[];
      final sub = state.watch('a').listen(seen.add);
      w
        ..set('b', 9)
        ..set('a', 1);
      await settle();
      expect(seen, [null, 1]);
      await sub.cancel();
    });
  });

  group('LocalHub', () {
    test('a batch commits once; reads inside see its own writes', () async {
      final hub = LocalHub();
      final a = LocalState<int>(hub: hub);
      final b = LocalKeyedState<String, int>(hub: hub);
      final s = LocalFact<String>(hub: hub);
      final wa = a.claim();
      final wb = b.claim();
      final e = s.claim();
      final ticks = <LocalTick>[];
      final sub = hub.ticks.listen(ticks.add);

      hub.batch(() {
        wa.set(1, tag: 'why');
        expect(a.value, 1);
        expect(a.has, isFalse);
        wb.set('k', 2);
        e.emit('done');
      });
      await settle();

      expect(ticks, hasLength(1));
      final t = ticks.single;
      expect([t.from, t.to], [1, 3]);
      expect(t.changes.map((c) => c.seq), [1, 2]);
      expect(t.changes.first.tag, 'why');
      expect(t.changes.first.state, same(a));
      expect(t.facts.single.seq, 3);
      await sub.cancel();
    });

    test('batches nest; the outermost commits', () {
      final hub = LocalHub();
      final w = LocalState<int>(hub: hub).claim();
      hub.batch(() {
        hub.batch(() => w.set(1));
        expect(hub.seq, 0);
      });
      expect(hub.seq, 1);
    });

    test('a batch that throws commits nothing it wrote or said; an outer '
        'one keeps what it wrote before', () async {
      final hub = LocalHub();
      final state = LocalState<int>(hub: hub);
      final w = state.claim();
      final fact = LocalFact<int>(hub: hub);
      final say = fact.claim();
      final heard = <int>[];
      final sub = fact.stream.listen(heard.add);
      expect(
        () => hub.batch(() {
          w.set(1);
          say.emit(1);
          throw StateError('midway');
        }),
        throwsStateError,
      );
      expect((state.value, hub.seq), (null, 0));
      hub.batch(() {
        w.set(2);
        try {
          hub.batch(() {
            w.set(3);
            throw StateError('inner');
          });
        } on StateError {
          // The outer goes on with what it wrote itself.
        }
      });
      expect(state.value, 2);
      await settle();
      expect(heard, isEmpty);
      await sub.cancel();
    });

    test('a batch is synchronous', () {
      final hub = LocalHub();
      expect(() => hub.batch(() async {}), throwsArgumentError);
    });

    test('onCommit sees a tick before the stream does', () async {
      final order = <String>[];
      final hub = LocalHub(onCommit: (_) => order.add('commit'));
      final sub = hub.ticks.listen((_) => order.add('stream'));
      LocalState<int>(hub: hub).claim().set(1);
      order.add('after write');
      await settle();
      expect(order, ['commit', 'after write', 'stream']);
      await sub.cancel();
    });
  });

  group('LocalFact', () {
    test('one emitter unless open', () {
      final closed = LocalFact<int>();
      closed.claim();
      expect(closed.claim, throwsStateError);
      final open = LocalFact<int>(open: true);
      open.claim();
      expect(open.claim, returnsNormally);
    });

    test('emits reach the stream, with no value kept', () async {
      final s = LocalFact<int>();
      final e = s.claim();
      final seen = <int>[];
      final sub = s.stream.listen(seen.add);
      e
        ..emit(1)
        ..emit(2);
      await settle();
      expect(seen, [1, 2]);
      await sub.cancel();
    });
  });

  group('LocalCommand', () {
    test('answers what its one handler answers', () async {
      final command = LocalCommand<int, String>();
      final serving = command.serve((n) => '$n!');
      expect(() => command.serve((n) => ''), throwsStateError);
      expect(await command.call(2), '2!');
      serving.dispose();
      expect(command.served, isFalse);
      await expectLater(command.call(1), throwsStateError);
    });

    test('a handler that throws fails the call', () async {
      final command = LocalCommand<int, int>()
        ..serve((_) => throw StateError('no'));
      await expectLater(command.call(1), throwsStateError);
    });
  });
}
