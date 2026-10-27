import 'package:parlance/core.dart';
import 'package:test/test.dart';

void main() {
  test('a batch that throws commits nothing of what was closed in it', () {
    final ticks = <HubTick>[];
    final hub = Hub(onCommit: ticks.add);
    final gone = Cell<int>(hub: hub);
    final goneWriter = gone.claim();
    final said = Signal<int>(hub: hub);
    final saying = said.claim();
    final kept = Cell<int>(hub: hub);
    final keptWriter = kept.claim();

    hub.batch(() {
      goneWriter.set(1);
      saying.emit(1);
      keptWriter.set(1);
      expect(
        () => hub.batch(() {
          gone.close();
          said.close();
          throw StateError('no');
        }),
        throwsStateError,
      );
    });

    expect(ticks.single.changes.map((c) => c.store), [kept]);
    expect(ticks.single.emits, isEmpty);
    expect(gone.has, isFalse);
  });

  test('clearing a keyed cell removes what is committed and what waits', () {
    final ticks = <HubTick>[];
    final hub = Hub(onCommit: ticks.add);
    final cell = KeyedCell<String, int>(hub: hub);
    final writer = cell.claim();
    writer.set('a', 1);

    hub.batch(() {
      writer.set('b', 2);
      writer.clear(tag: 'gone');
    });

    expect(cell.values, isEmpty);
    expect(ticks.last.changes.map((c) => (c.key, c.removed, c.tag)), [
      ('a', true, 'gone'),
    ]);
  });
}
