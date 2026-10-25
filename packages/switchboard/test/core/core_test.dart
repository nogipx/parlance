import 'dart:async';

import 'package:switchboard/core.dart';
import 'package:test/test.dart';

/// The core (SPEC §21): cells, signals, ports and the hub.
void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('Cell', () {
    test('one writer at a time; another may claim after it is released', () {
      final cell = Cell<int>();
      final w = cell.claim();
      expect(cell.claim, throwsStateError);
      w.dispose();
      expect(() => w.set(1), throwsStateError);
      expect(cell.claim, returnsNormally);
    });

    test('a write commits at once outside a batch', () {
      final cell = Cell<int>();
      cell.claim().set(1);
      expect(cell.value, 1);
      expect(cell.has, isTrue);
    });

    test('watch gives the value now, then every change', () async {
      final cell = Cell<int>();
      final w = cell.claim()..set(1);
      final seen = <int?>[];
      final sub = cell.watch().listen(seen.add);
      w
        ..set(2)
        ..remove();
      await settle();
      expect(seen, [1, 2, null]);
      await sub.cancel();
    });

    test('an equal value commits nothing', () async {
      final hub = Hub();
      final cell = Cell<List<int>>(
        hub: hub,
        equals: (a, b) => a.length == b.length,
      );
      final w = cell.claim()..set([1]);
      final seq = hub.seq;
      w.set([2]);
      expect(hub.seq, seq);
      expect(cell.value, [1]);
    });

    test('close drops what waits in a batch and refuses writers', () {
      final hub = Hub();
      final cell = Cell<int>(hub: hub);
      final w = cell.claim();
      hub.batch(() {
        w.set(1);
        cell.close();
      });
      expect(cell.has, isFalse);
      expect(hub.seq, 0);
      expect(cell.claim, throwsStateError);
    });
  });

  group('KeyedCell', () {
    test('a value per key; removing an absent key commits nothing', () {
      final hub = Hub();
      final cell = KeyedCell<String, int>(hub: hub);
      final w = cell.claim()
        ..set('a', 1)
        ..set('b', 2)
        ..remove('c');
      expect(cell.values, {'a': 1, 'b': 2});
      expect(hub.seq, 2);
      w.remove('a');
      expect(cell.has('a'), isFalse);
    });

    test('watch follows one key', () async {
      final cell = KeyedCell<String, int>();
      final w = cell.claim();
      final seen = <int?>[];
      final sub = cell.watch('a').listen(seen.add);
      w
        ..set('b', 9)
        ..set('a', 1);
      await settle();
      expect(seen, [null, 1]);
      await sub.cancel();
    });
  });

  group('Hub', () {
    test('a batch commits once; reads inside see its own writes', () async {
      final hub = Hub();
      final a = Cell<int>(hub: hub);
      final b = KeyedCell<String, int>(hub: hub);
      final s = Signal<String>(hub: hub);
      final wa = a.claim();
      final wb = b.claim();
      final e = s.claim();
      final ticks = <HubTick>[];
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
      expect(t.changes.first.store, same(a));
      expect(t.emits.single.seq, 3);
      await sub.cancel();
    });

    test('batches nest; the outermost commits', () {
      final hub = Hub();
      final w = Cell<int>(hub: hub).claim();
      hub.batch(() {
        hub.batch(() => w.set(1));
        expect(hub.seq, 0);
      });
      expect(hub.seq, 1);
    });

    test('a batch is synchronous', () {
      final hub = Hub();
      expect(() => hub.batch(() async {}), throwsArgumentError);
    });

    test('onCommit sees a tick before the stream does', () async {
      final order = <String>[];
      final hub = Hub(onCommit: (_) => order.add('commit'));
      final sub = hub.ticks.listen((_) => order.add('stream'));
      Cell<int>(hub: hub).claim().set(1);
      order.add('after write');
      await settle();
      expect(order, ['commit', 'after write', 'stream']);
      await sub.cancel();
    });
  });

  group('Signal', () {
    test('one emitter unless open', () {
      final closed = Signal<int>();
      closed.claim();
      expect(closed.claim, throwsStateError);
      final open = Signal<int>(open: true);
      open.claim();
      expect(open.claim, returnsNormally);
    });

    test('emits reach the stream, with no value kept', () async {
      final s = Signal<int>();
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

  group('Port', () {
    test('answers what its one handler answers', () async {
      final port = Port<int, String>();
      final serving = port.serve((n) => '$n!');
      expect(() => port.serve((n) => ''), throwsStateError);
      expect(await port.call(2), '2!');
      serving.dispose();
      expect(port.served, isFalse);
      await expectLater(port.call(1), throwsStateError);
    });

    test('a handler that throws fails the call', () async {
      final port = Port<int, int>()..serve((_) => throw StateError('no'));
      await expectLater(port.call(1), throwsStateError);
    });
  });
}
