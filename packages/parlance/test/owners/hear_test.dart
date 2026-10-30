import 'package:parlance/tools.dart';
import 'package:parlance/schema.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:test/test.dart';

part 'hear_test.g.dart';

/// What an owner does on hearing another's fact follows from that fact,
/// as a handler's follows from its call (SPEC §4): no cause passed. And a
/// fact said for another follows from what is being answered too.
@Vocabulary('door')
abstract class Door {
  @FactWord('rang')
  void rang({required String who});
}

@Vocabulary('book')
abstract class Book {
  @StateWord('last')
  String get last;
}

final class _Door extends DoorOwnerBase {}

final class _Book extends BookOwnerBase {
  _Book() {
    hear(fact: IDoorClient.of(this).rang, onData: (r) => last.set(r.who));
  }
}

void main() {
  test('what it does on hearing a fact follows from the fact', () async {
    final r = Registry();
    addTearDown(r.dispose);
    final door = _Door();
    r.participant(
      const Principal('door'),
      owners: [door],
      rights: ParticipantRights(speakFor: (_) => null),
    );
    r.participant(const Principal('book'), owners: [_Book()]);
    await pumpEventQueue();

    door.rang.say(who: 'ann', by: const Principal('guest', 'ann'));
    await pumpEventQueue();
    final said = r.recent('door.rang', 1).single;
    expect(said.cause.by, const Principal('guest', 'ann'));
    final change = r.explain('book.last').change!;
    expect(r.read('book.last'), 'ann');
    expect(change.cause.parent, said.id);
    expect(change.cause.by, const Principal('book').ofOwner('book'));
  });
}
