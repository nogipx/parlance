import 'package:parlance/registry.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

/// A guard a part keeps across a connection judges the calls of its own
/// commands only (SPEC §10): any other call is not held up asking it, so
/// its handler begins as the call is made, as with no such guard.
void main() {
  late TestHost host;
  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  test('a call of a command the guard does not judge is not held up', () async {
    var ran = false;
    host
        .participant(
          const Principal('deck'),
          vocabularies: [WordSet.open('deck')],
        )
        .defineCommand(
          CommandDescriptor('deck.go', callers: Callers.only(['user'])),
          (_) => ran = true,
        );
    final guest = await host.join(
      const Principal('widlet', 'b'),
      vocabularies: [WordSet.open('widlet')],
    );
    guest
      ..defineCommand(
        CommandDescriptor('widlet.do', callers: Callers.only(['user'])),
        (_) {},
      )
      ..addGuard('quiet', (_) => 'no');
    await guest.flush();
    final done = host.registry.call('deck.go', {}, by: const Principal('user'));
    expect(ran, isTrue, reason: 'begun as it was called');
    expect(await done, isA<CallDone<Object?>>());
    expect(
      await host.registry.call('widlet.do', {}, by: const Principal('user')),
      isA<CallRefused>(),
      reason: 'its own command it still judges',
    );
  });
}
