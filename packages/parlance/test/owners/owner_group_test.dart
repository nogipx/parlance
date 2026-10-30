import 'package:parlance/schema.dart';
import 'package:parlance/tools.dart';
import 'package:test/test.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/src/participant/local.dart' show Participants;

part 'owner_group_test.g.dart';

const me = Principal('host');

@Vocabulary('a')
abstract class A {
  @StateWord('level')
  int get level;
}

@Vocabulary('b')
abstract class B {
  @StateWord('level')
  int get level;
}

@Vocabulary('c')
abstract class C {
  @StateWord('level')
  int get level;
}

/// Writes [value] to its level whenever it is synced, or throws when
/// [fails]; [defineFails] fails it as it is attached.
mixin _Level {
  bool fails = false;
  int value = 0;

  Single<int> get level;

  void pull() {
    level.set(value);
    if (fails) throw StateError('cannot sync');
  }
}

final class LevelA extends AOwnerBase with _Level {
  LevelA({bool defineFails = false}) {
    follow(pull: pull);
    if (defineFails) whenAttached((_) => throw StateError('cannot define'));
  }
}

final class LevelB extends BOwnerBase with _Level {
  LevelB({bool defineFails = false}) {
    follow(pull: pull);
    if (defineFails) whenAttached((_) => throw StateError('cannot define'));
  }
}

final class LevelC extends COwnerBase with _Level {
  LevelC() {
    follow(pull: pull);
  }
}

void main() {
  late Registry r;
  setUp(() => r = Registry());
  tearDown(() => r.dispose());

  /// The participant of [owners].
  LocalParticipant mix(List<IOwner> owners) =>
      r.participant(me, owners: owners);

  test('an owner whose sync throws writes nothing; the others write what '
      'they have', () {
    final good = LevelA();
    final bad = LevelB();
    final p = mix([good, bad]);
    good.value = 1;
    bad
      ..value = 1
      ..fails = true;
    expect(p.sync, throwsStateError);
    expect(r.read('a.level'), 1);
    expect(r.read('b.level'), 0);
  });

  test('owners are attached all or none, and the participant goes with '
      'them', () {
    expect(() => mix([LevelA(), LevelB(defineFails: true)]), throwsStateError);
    expect(r.stateDescriptor('a.level'), isNull);
    expect(r.stateDescriptor('b.level'), isNull);
    mix([LevelA()]);
    expect(r.read('a.level'), 0, reason: 'its principal and a are free');
  });

  test(
    'an owner attached elsewhere is refused before anything is attached',
    () {
      final twice = LevelA();
      mix([twice]);
      expect(
        () =>
            r.participant(const Principal('other'), owners: [LevelC(), twice]),
        throwsStateError,
      );
      expect(r.stateDescriptor('c.level'), isNull);
      expect(r.stateDescriptor('a.level'), isNotNull);
    },
  );
}
