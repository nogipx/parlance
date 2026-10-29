import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

/// A batch is whole or nothing (SPEC §7), wherever the participant is:
/// when its body throws, nothing it wrote or said is committed, its own
/// states are as they were, and an outer batch that catches it keeps what
/// it wrote itself.
void main() {
  late TestHost host;
  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  const deck = Principal('deck');

  for (final across in [false, true]) {
    group(across ? 'across a connection' : 'in this process', () {
      Future<IParticipant> owner() async {
        final vocabularies = [WordSet.open('deck')];
        if (!across) {
          return host.participant(deck, vocabularies: vocabularies);
        }
        final p = await host.join(deck, vocabularies: vocabularies);
        await p.settle();
        return p;
      }

      Future<void> settled(IParticipant p) async {
        if (p is RemoteParticipant) await p.flush();
        await pumpEventQueue();
      }

      test('a batch that throws commits nothing it wrote or said', () async {
        final p = await owner();
        final volume = p.raw.defineState(
          StateDescriptor('deck.volume', type: const IntType()),
        );
        final said = p.raw.defineFact(
          FactDescriptor('deck.said', type: const IntType()),
        );
        volume.set(1);
        await settled(p);
        final heard = <Object?>[];
        host.registry.facts(fact: 'deck.said').listen((FactMessage f) {
          heard.add(f.payload);
        });
        expect(
          () => p.batch(() {
            volume.set(2);
            said.emit(2);
            throw StateError('no');
          }),
          throwsStateError,
        );
        await settled(p);
        expect(host.registry.read('deck.volume'), 1);
        expect(p.read('deck.volume'), 1, reason: 'its own copy too');
        expect(heard, isEmpty);
      });

      test(
        'an outer batch that catches an inner one keeps what it wrote',
        () async {
          final p = await owner();
          final a = p.raw.defineState(
            StateDescriptor('deck.a', type: const IntType()),
          );
          final b = p.raw.defineState(
            StateDescriptor('deck.b', type: const IntType()),
          );
          p.batch(() {
            a.set(1);
            try {
              p.batch(() {
                b.set(1);
                a.set(9);
                throw StateError('inner');
              });
            } on StateError {
              // kept going
            }
          });
          await settled(p);
          expect(host.registry.read('deck.a'), 1);
          expect(host.registry.read('deck.b'), isNull);
          expect(p.read('deck.a'), 1);
          expect(p.read('deck.b'), isNull);
        },
      );
    });
  }
}
