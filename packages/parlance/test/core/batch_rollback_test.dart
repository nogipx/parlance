import 'package:parlance/src/core/core.dart';
import 'package:test/test.dart';

void main() {
  test('a batch that throws commits nothing of what was closed in it', () {
    final ticks = <LocalTick>[];
    final hub = LocalHub(onCommit: ticks.add);
    final gone = LocalState<int>(hub: hub);
    final goneWriter = gone.claim();
    final said = LocalFact<int>(hub: hub);
    final saying = said.claim();
    final kept = LocalState<int>(hub: hub);
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

    expect(ticks.single.changes.map((c) => c.state), [kept]);
    expect(ticks.single.facts, isEmpty);
    expect(gone.has, isFalse);
  });

  test('clearing a keyed state removes what is committed and what waits', () {
    final ticks = <LocalTick>[];
    final hub = LocalHub(onCommit: ticks.add);
    final state = LocalKeyedState<String, int>(hub: hub);
    final writer = state.claim();
    writer.set('a', 1);

    hub.batch(() {
      writer.set('b', 2);
      writer.clear(tag: 'gone');
    });

    expect(state.values, isEmpty);
    expect(ticks.last.changes.map((c) => (c.key, c.removed, c.tag)), [
      ('a', true, 'gone'),
    ]);
  });
}
