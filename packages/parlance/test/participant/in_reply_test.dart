import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

/// What a handler does with no cause given follows from the call it
/// serves (SPEC §4), as `call.causeFor(who)` would make it: a write, a
/// fact, a call of its own, before an `await` and after it, wherever the
/// participant is. What it does outside a handler is its own act.
void main() {
  late TestHost host;
  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  const deck = Principal('deck');
  const user = Principal('user');

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

      test('a write, a fact and a call, before an await and after, follow '
          'from the call served', () async {
        final p = await owner();
        final before = p.raw.defineState(
          StateDescriptor('deck.before', type: const IntType()),
        );
        final after = p.raw.defineState(
          StateDescriptor('deck.after', type: const IntType()),
        );
        final said = p.raw.defineFact(
          FactDescriptor('deck.said', type: const IntType()),
        );
        String? innerParent;
        p.raw.defineCommand(
          CommandDescriptor('deck.inner', callers: Callers.only(['deck'])),
          (c) => innerParent = c.cause.parent,
        );
        p.raw.defineCommand(
          CommandDescriptor('deck.go', callers: Callers.only(['user'])),
          (c) async {
            before.set(1);
            await Future<void>.delayed(Duration.zero);
            after.set(2);
            said.emit(3);
            await p.raw.call('deck.inner', {});
          },
        );
        await settled(p);
        final facts = <FactMessage>[];
        host.registry.facts(fact: 'deck.said').listen(facts.add);
        final r = await host
            .participant(user)
            .raw
            .call('deck.go', {}, id: 'go1');
        expect(r, isA<CallDone<Object?>>());
        await settled(p);
        for (final s in ['deck.before', 'deck.after']) {
          final change = host.registry.explain(s).change!;
          expect(change.cause.parent, 'go1', reason: s);
          expect(change.cause.by, deck);
        }
        expect(facts.single.cause.parent, 'go1');
        expect(innerParent, 'go1');
      });

      test('outside a handler, what it does is its own act', () async {
        final p = await owner();
        final level = p.raw.defineState(
          StateDescriptor('deck.level', type: const IntType()),
        );
        level.set(1);
        await settled(p);
        final change = host.registry.explain('deck.level').change!;
        expect(change.cause.parent, isNull);
        expect(change.cause.by, deck);
      });
    });
  }
}
