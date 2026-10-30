import 'package:parlance/tools.dart';
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

/// A word renamed while a part follows it by its old name (SPEC §6.4): the
/// old name stands for the word, so the part goes on reading and hearing
/// it as it did, with no new subscription of its own.
void main() {
  late TestHost host;
  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  const deck = Principal('deck');

  test('a state renamed live goes on reaching a part that follows its old '
      'name', () async {
    final owner = host.participant(deck, vocabularies: [WordSet.open('deck')]);
    final old = owner.raw.defineState(
      StateDescriptor('deck.old', type: const IntType()),
    )..set(1);
    final guest = await host.join(const Principal('widlet', 'b'));
    final seen = <Object?>[];
    final sub = guest.raw.watch('deck.old').listen(seen.add);
    await guest.raw.fetch('deck.old');
    await pumpEventQueue();
    expect(guest.raw.read('deck.old'), 1);

    // The owner comes back with the word renamed; the host keeps the old
    // name for it.
    old.dispose();
    final now = owner.raw.defineState(
      StateDescriptor('deck.new', type: const IntType()),
    );
    host.registry.alias('deck.old', 'deck.new');
    now.set(5);
    for (var i = 0; i < 10; i++) {
      await pumpEventQueue();
    }
    expect(guest.raw.read('deck.old'), 5);
    expect(seen.last, 5);
    await sub.cancel();
  });

  test('a fact renamed live goes on reaching a part that hears its old '
      'name', () async {
    final owner = host.participant(deck, vocabularies: [WordSet.open('deck')]);
    final old = owner.raw.defineFact(
      FactDescriptor('deck.said', type: const IntType()),
    );
    final guest = await host.join(const Principal('widlet', 'b'));
    final heard = <Object?>[];
    final sub = guest.raw
        .facts('deck.said')
        .listen((f) => heard.add(f.payload));
    await guest.settle();
    await pumpEventQueue();
    old.say(1);
    await pumpEventQueue();
    old.dispose();
    final now = owner.raw.defineFact(
      FactDescriptor('deck.told', type: const IntType()),
    );
    host.registry.alias('deck.said', 'deck.told');
    for (var i = 0; i < 10; i++) {
      await pumpEventQueue();
    }
    now.say(2);
    for (var i = 0; i < 10; i++) {
      await pumpEventQueue();
    }
    expect(heard, [1, 2]);
    await sub.cancel();
  });

  test(
    'in this process too: a watch of the old name follows the word',
    () async {
      final owner = host.participant(
        deck,
        vocabularies: [WordSet.open('deck')],
      );
      final old = owner.raw.defineState(
        StateDescriptor('deck.old', type: const IntType()),
      )..set(1);
      final reader = host.participant(const Principal('screen'));
      final seen = <Object?>[];
      final sub = reader.raw.watch('deck.old').listen(seen.add);
      await pumpEventQueue();
      old.dispose();
      final now = owner.raw.defineState(
        StateDescriptor('deck.new', type: const IntType()),
      );
      host.registry.alias('deck.old', 'deck.new');
      now.set(5);
      await pumpEventQueue();
      expect(reader.raw.read('deck.old'), 5);
      expect(seen.last, 5);
      await sub.cancel();
    },
  );
}
