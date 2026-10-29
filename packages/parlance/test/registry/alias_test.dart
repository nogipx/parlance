import 'package:parlance/tools.dart';
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
    final h = f.r.alias('door.silenced', 'door.locked');
    f.r.alias('door.hush', 'door.lock');
    expect(f.r.canonical('door.silenced'), 'door.locked');
    expect(f.r.stateDescriptor('door.silenced')?.name, 'door.locked');

    final done = await f.r.call('door.hush', {'on': true}, by: user);
    expect(done, isA<CallDone<Object?>>());
    expect(f.r.read('door.silenced'), true);
    expect(f.r.readAll('door.silenced'), {null: true});
    expect(f.r.describe()['aliases'], {
      'door.silenced': 'door.locked',
      'door.hush': 'door.lock',
    });

    h.dispose();
    expect(f.r.read('door.silenced'), isNull);
    expect(f.r.describe()['aliases'], {'door.hush': 'door.lock'});
  });

  test('an old name is not a word: it is refused as one, and no word may '
      'take it', () {
    f.r.alias('door.silenced', 'door.locked');
    expect(() => f.r.alias('door.locked', 'house.focus'), throwsStateError);
    expect(
      () => f.r.defineState(
        StateDescriptor('door.silenced', type: const BoolType()),
        by: owner,
      ),
      throwsStateError,
    );
  });

  test('over remote, an old name subscribes to and reads the word', () async {
    f.r.alias('door.silenced', 'door.locked');
    f.locked.set(true);
    final link = Link.open(f.r, user, wire: false);
    addTearDown(link.close);
    final mirror = RegistryMirror()..follow(link.client);
    addTearDown(mirror.dispose);
    await mirror.subscribe(states: {'door.silenced'});
    await settle();
    expect(mirror.read('door.silenced'), true);
    expect(mirror.read('door.locked'), true);
  });
}
