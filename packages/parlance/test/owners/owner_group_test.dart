import 'package:parlance/tools.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/owner.dart' show IOwner, Owner;
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const me = Principal('host');

/// Writes [value] to its state on every sync, or throws when [fails].
final class Level extends Owner {
  Level(this.name, {this.fails = false, this.defineFails = false});

  final String name;
  bool fails;
  final bool defineFails;
  int value = 0;
  late final IStateHandle _state;

  @override
  void define(IRawParticipant p) {
    _state = keep(p.defineState(StateDescriptor(name, type: const IntType())));
    if (defineFails) throw StateError('cannot define');
  }

  @override
  void sync() {
    _state.set(value);
    if (fails) throw StateError('cannot sync');
  }
}

void main() {
  late Registry r;
  setUp(() => r = Registry());
  tearDown(() => r.dispose());

  /// The participant of [owners], in the vocabulary mix.
  LocalParticipant mix(List<IOwner> owners) => r.participant(
    me,
    owners: owners,
    vocabularies: [const WordSet.open('mix')],
  );

  test('an owner whose sync throws writes nothing; the others write what '
      'they have', () {
    final good = Level('mix.a');
    final bad = Level('mix.b');
    final p = mix([good, bad]);
    good.value = 1;
    bad
      ..value = 1
      ..fails = true;
    expect(p.sync, throwsStateError);
    expect(r.read('mix.a'), 1);
    expect(r.read('mix.b'), 0);
  });

  test('an owner disposed on its own is synced no more', () {
    final gone = Level('mix.a');
    final kept = Level('mix.b');
    final p = mix([gone, kept]);
    gone.dispose();
    kept.value = 2;
    p.sync();
    expect(r.read('mix.b'), 2);
    expect(r.stateDescriptor('mix.a'), isNull);
  });

  test('owners are attached all or none, and the participant goes with '
      'them', () {
    expect(
      () => mix([Level('mix.a'), Level('mix.b', defineFails: true)]),
      throwsStateError,
    );
    expect(r.stateDescriptor('mix.a'), isNull);
    expect(r.stateDescriptor('mix.b'), isNull);
    mix([Level('mix.a')]);
    expect(r.read('mix.a'), 0, reason: 'its principal and mix are free');
  });

  test(
    'an owner attached elsewhere is refused before anything is attached',
    () {
      final twice = Level('mix.a');
      mix([twice]);
      expect(
        () => r.participant(
          const Principal('other'),
          owners: [Level('other.b'), twice],
          vocabularies: [const WordSet.open('other')],
        ),
        throwsStateError,
      );
      expect(r.stateDescriptor('other.b'), isNull);
      expect(r.stateDescriptor('mix.a'), isNotNull);
    },
  );
}
