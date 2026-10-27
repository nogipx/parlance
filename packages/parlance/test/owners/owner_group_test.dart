import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

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
  void define(IParticipant p) {
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
  late LocalParticipant p;
  setUp(() {
    r = Registry();
    p = r.participant(me, vocabularies: [const WordSet.open('mix')]);
  });
  tearDown(() => r.dispose());

  test('an owner whose sync throws writes nothing; the others write what '
      'they have', () {
    final good = Level('mix.a');
    final bad = Level('mix.b');
    p.attach({'a': good, 'b': bad});
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
    p.attach({'a': gone, 'b': kept});
    gone.dispose();
    kept.value = 2;
    p.sync();
    expect(r.read('mix.b'), 2);
    expect(r.stateDescriptor('mix.a'), isNull);
  });

  test('owners are attached all or none', () {
    expect(
      () => p.attach({
        'a': Level('mix.a'),
        'b': Level('mix.b', defineFails: true),
      }),
      throwsStateError,
    );
    expect(r.stateDescriptor('mix.a'), isNull);
    expect(r.stateDescriptor('mix.b'), isNull);
    p.attach({'a': Level('mix.a')});
    expect(r.read('mix.a'), 0);
  });

  test(
    'an owner attached elsewhere is refused before anything is attached',
    () {
      final twice = Level('mix.a');
      p.attach({'a': twice});
      final other = r.participant(
        const Principal('other'),
        vocabularies: [const WordSet.open('other')],
      );
      expect(
        () => other.attach({'b': Level('other.b'), 'a': twice}),
        throwsStateError,
      );
      expect(r.stateDescriptor('other.b'), isNull);
      expect(r.stateDescriptor('mix.a'), isNotNull);
    },
  );
}
