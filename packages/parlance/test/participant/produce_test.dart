import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

/// Saying another's fact (SPEC §7) is refused where it is said, wherever
/// the participant is: one only its owner says, at once; a payload of
/// the wrong type, at once, not later on errors.
String? anyFact(Principal who, String fact) => null;

void main() {
  late TestHost host;
  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  const guest = Principal('widlet', 'b');
  const rights = ParticipantRights(produce: anyFact);

  for (final across in [false, true]) {
    group(across ? 'across a connection' : 'in this process', () {
      Future<IParticipant> producer() async {
        final deck = host.participant(
          const Principal('deck'),
          vocabularies: [WordSet.open('deck')],
        );
        deck.defineFact(
          FactDescriptor('deck.said', type: const IntType(), open: true),
        );
        deck.defineFact(FactDescriptor('deck.own', type: const IntType()));
        if (!across) return host.participant(guest, rights: rights);
        final p = await host.join(guest, rights: rights);
        await p.settle();
        return p;
      }

      test('a fact only its owner says is refused at once', () async {
        final p = await producer();
        expect(() => p.producer('deck.own'), throwsStateError);
      });

      test('a payload of the wrong type is refused at once', () async {
        final p = await producer();
        final said = p.producer('deck.said');
        expect(() => said.emit('loud'), throwsA(isA<TypeMismatch>()));
        expect(said.emit(3), isTrue);
      });
    });
  }
}
