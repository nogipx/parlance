import 'package:fake_async/fake_async.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

/// A state trigger at its edges: a link that comes when the state already
/// holds, and a value that comes or goes rather than changes.
void main() {
  late LinksFixture f;
  setUp(() => f = LinksFixture());
  tearDown(() => f.links.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Map<String, Object?> sayWhen(Map<String, Object?> trigger) => {
    'id': 'say',
    'when': [trigger],
    'do': [
      {
        'call': 'test.say',
        'params': {'text': r'$trigger.key'},
      },
    ],
  };

  test('a link that comes while its state already holds waits for a change, '
      'unless it says already', () async {
    f.muted.set(true);
    await settle();
    f.use([
      sayWhen({'state': 'audio.muted', 'becomes': true}),
    ]);
    await settle();
    expect(f.said, isEmpty, reason: 'nothing became true');

    f.use([
      sayWhen({'state': 'audio.muted', 'becomes': true, 'already': true}),
    ]);
    await settle();
    expect(f.said, hasLength(1), reason: 'it already holds');
  });

  test(
    'a value that comes where there was none is not a change of it',
    () async {
      f.use([
        sayWhen({'state': 'late.on', 'becomes': true}),
      ]);
      await settle();
      final late = f.r.defineState(
        StateDescriptor('late.on', type: const BoolType()),
        by: owner,
      );
      await settle();
      late.set(true);
      await settle();
      expect(f.said, isEmpty, reason: 'its first value, no edge');
      late.set(false);
      late.set(true);
      await settle();
      expect(f.said, hasLength(1), reason: 'a change, and the edge');
    },
  );

  test('a key that comes, or goes, is no edge; already takes the one that '
      'comes holding', () async {
    f.use([
      sayWhen({
        'state': 'audio.gain',
        'changes': {'to': 0},
      }),
    ]);
    await settle();
    f.gain.set(0, key: 'mic');
    await settle();
    expect(f.said, isEmpty);
    f.gain.remove(key: 'mic');
    await settle();
    expect(f.said, isEmpty, reason: 'gone is not a change');

    f.use([
      sayWhen({
        'state': 'audio.gain',
        'changes': {'to': 0},
        'already': true,
      }),
    ]);
    await settle();
    f.gain.set(0, key: 'mic');
    await settle();
    expect(f.said, ['mic']);
  });

  test('already with for: it must go on holding that long from the start', () {
    fakeAsync((async) {
      final g = LinksFixture(
        registry: Registry(
          overriders: {'user'},
          onError: (e, st) => throw e,
          clock: async.getClock(DateTime(2026)),
        ),
      );
      g.muted.set(true);
      async.flushMicrotasks();
      g.use([
        {
          'id': 'say',
          'when': [
            {
              'state': 'audio.muted',
              'becomes': true,
              'for': '1m',
              'already': true,
            },
          ],
          'do': [
            {
              'call': 'test.say',
              'params': {'text': 'long'},
            },
          ],
        },
      ]);
      async.elapse(const Duration(seconds: 30));
      expect(g.said, isEmpty);
      async.elapse(const Duration(seconds: 31));
      expect(g.said, ['long']);
      g.links.dispose();
    });
  });

  test('already without an edge to hold is refused', () {
    expect(
      f.links.apply([
        sayWhen({
          'state': 'audio.muted',
          'changes': <String, Object?>{},
          'already': true,
        }),
      ]),
      isNotEmpty,
    );
  });
}
