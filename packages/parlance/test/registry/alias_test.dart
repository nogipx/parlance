import 'package:parlance/registry.dart';
import 'package:parlance/src/remote/mirror.dart';
import 'package:test/test.dart';

import '../remote/remote_test.dart' show Link, settle;
import 'fixture.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

/// A word renamed answers to its old name: what named it keeps working.
void main() {
  late Fixture f;
  setUp(() => f = Fixture());
  tearDown(() => f.r.dispose());

  test('calls, reads, watches and the catalog take an old name', () async {
    final h = f.r.alias('audio.silenced', 'audio.muted');
    f.r.alias('audio.hush', 'audio.mute');
    expect(f.r.canonical('audio.silenced'), 'audio.muted');
    expect(f.r.stateDescriptor('audio.silenced')?.name, 'audio.muted');

    final done = await f.r.call('audio.hush', {'on': true}, by: user);
    expect(done, isA<CallDone<Object?>>());
    expect(f.r.read('audio.silenced'), true);
    expect(f.r.readAll('audio.silenced'), {null: true});
    expect(f.r.describe()['aliases'], {
      'audio.silenced': 'audio.muted',
      'audio.hush': 'audio.mute',
    });

    h.dispose();
    expect(f.r.read('audio.silenced'), isNull);
    expect(f.r.describe()['aliases'], {'audio.hush': 'audio.mute'});
  });

  test('an old name is not a word: it is refused as one, and no word may '
      'take it', () {
    f.r.alias('audio.silenced', 'audio.muted');
    expect(() => f.r.alias('audio.muted', 'studio.program'), throwsStateError);
    expect(
      () => f.r.defineState(
        StateDescriptor('audio.silenced', type: const BoolType()),
        by: owner,
      ),
      throwsStateError,
    );
  });

  test('over remote, an old name subscribes to and reads the word', () async {
    f.r.alias('audio.silenced', 'audio.muted');
    f.muted.set(true);
    final link = Link.open(f.r, user, wire: false);
    addTearDown(link.close);
    final mirror = RegistryMirror()..follow(link.client);
    addTearDown(mirror.dispose);
    await mirror.subscribe(states: {'audio.silenced'});
    await settle();
    expect(mirror.read('audio.silenced'), true);
    expect(mirror.read('audio.muted'), true);
  });
}
