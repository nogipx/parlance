import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

/// A name a participant holds is taken (SPEC §6), wherever it is: defined
/// again it is refused at once, and what it holds stays; once it lets the
/// word go, the name is free again.
void main() {
  late TestHost host;
  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  const deck = Principal('deck');

  for (final across in [false, true]) {
    group(across ? 'across a connection' : 'in this process', () {
      Future<IParticipant> owner() async {
        final vocabularies = [WordSet.open('deck')];
        if (!across) return host.participant(deck, vocabularies: vocabularies);
        final p = await host.join(deck, vocabularies: vocabularies);
        await p.settle();
        return p;
      }

      Future<void> settled(IParticipant p) async {
        await p.settle();
        await pumpEventQueue();
      }

      test('a word defined again is refused, and keeps what it had', () async {
        final p = await owner();
        final lamp = p.raw.defineState(
          StateDescriptor('deck.lamp', type: const BoolType()),
        );
        lamp.set(true);
        await settled(p);
        expect(
          () => p.raw.defineState(
            StateDescriptor('deck.lamp', type: const BoolType()),
          ),
          throwsStateError,
        );
        expect(
          () => p.raw.defineCommand(
            CommandDescriptor('deck.lamp', callers: Callers.only(['user'])),
            (_) {},
          ),
          throwsStateError,
          reason: 'a name is one word, of whatever kind',
        );
        await settled(p);
        expect(p.raw.read('deck.lamp'), true);
        expect(host.registry.read('deck.lamp'), true);
      });

      test(
        'a guard or a kind added again is refused, the first kept',
        () async {
          final p = await owner();
          final guard = p.raw.addGuard('quiet', (_) => null);
          expect(() => p.raw.addGuard('quiet', (_) => 'no'), throwsStateError);
          final kind = p.raw.registerKind(
            EntityKind('deck.slot', list: () => []),
          );
          expect(
            () => p.raw.registerKind(EntityKind('deck.slot', list: () => [])),
            throwsStateError,
          );
          guard.dispose();
          kind.dispose();
          p
            ..raw.addGuard('quiet', (_) => null)
            ..raw.registerKind(EntityKind('deck.slot', list: () => []));
        },
      );

      test('a word let go frees its name', () async {
        final p = await owner();
        p.raw.defineState(StateDescriptor('deck.lamp', type: const BoolType()))
          ..set(true)
          ..dispose();
        await settled(p);
        p.raw
            .defineState(StateDescriptor('deck.lamp', type: const BoolType()))
            .set(false);
        await settled(p);
        expect(host.registry.read('deck.lamp'), false);
      });
    });
  }
}
