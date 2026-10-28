import 'package:parlance/registry.dart';
import 'package:parlance/src/remote/built.dart';
import 'package:test/test.dart';

/// What a participant across a connection tells its host it was built
/// against (SPEC §25.4): by fingerprint first, the schemas the host asks
/// for after, each word once.
void main() {
  final schema = {'is': 'state', 'type': const IntType().toJson()};

  test('it tells fingerprints, then the schemas the host does not know', () {
    final told = BuiltTold();
    final [op] = told.tell({'a.x': schema}, from: 'a_words 1.0.0');
    expect(op, {
      'op': 'built',
      'prints': {'a.x': fingerprintOf(schema)},
      'from': 'a_words 1.0.0',
    });
    expect(told.answered(op, const {}), isNull, reason: 'the host knew it');
    expect(
      told.answered(op, const {
        'unknown': ['a.x'],
      }),
      {
        'op': 'built',
        'words': {'a.x': schema},
        'from': 'a_words 1.0.0',
      },
    );
  });

  test('a word told again as it was is not told', () {
    final told = BuiltTold();
    told.tell({'a.x': schema});
    expect(
      told.tell({
        'a.x': {...schema},
      }),
      isEmpty,
    );
    expect(told.tell({'a.x': schema}, from: 'a_words 2.0.0'), hasLength(1));
  });

  test('a new session is told all of it; going, it lets go of all', () {
    final told = BuiltTold();
    told.tell({'a.x': schema});
    told.tell({'a.y': schema}, as: const Principal('widlet', 'b', 'screen'));
    expect(
      [for (final op in told.standing()) op['prints']],
      [
        {'a.x': fingerprintOf(schema)},
        {'a.y': fingerprintOf(schema)},
      ],
    );
    expect(told.forget(), [
      {'op': 'unbuilt'},
      {
        'op': 'unbuilt',
        'as': const Principal('widlet', 'b', 'screen').toJson(),
      },
    ]);
    expect(told.isEmpty, isTrue);
  });
}
