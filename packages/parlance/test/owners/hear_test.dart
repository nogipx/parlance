import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:test/test.dart';
import 'package:parlance/src/participant/owner.dart' show Owner;

/// What an owner does on hearing another's fact follows from that fact,
/// as a handler's follows from its call (SPEC §4): no cause passed. And a
/// fact said for another follows from what is being answered too.
enum _Fact<T> implements IFactWord<T> {
  rang<String>('door.rang', Plain(TextType()));

  const _Fact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

enum _State<T> implements IStateWord<T> {
  last<String>('book.last', Plain(TextType()));

  const _State(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

final class _Book extends Owner {
  _Book() : super(vocabulary: 'book');

  late final IStateWriterOf<String> _last;

  @override
  void define(IRawParticipant p) {
    _last = keep(p.state(_State.last).define());
    hear(fact: GeneratedWords.of(p).factOf(_Fact.rang), onData: _last.set);
  }
}

void main() {
  test('what it does on hearing a fact follows from the fact', () async {
    final r = Registry();
    addTearDown(r.dispose);
    final door = r.participant(
      const Principal('door'),
      vocabularies: [WordSet.open('door')],
      rights: ParticipantRights(speakFor: (_, _, _) => null),
    );
    final rang = door.fact(_Fact.rang).define();
    r
        .participant(
          const Principal('book'),
          vocabularies: [WordSet.open('book')],
        )
        .attach([_Book()]);
    await pumpEventQueue();

    rang.emitFor('ann', const Principal('guest', 'ann'));
    await pumpEventQueue();
    final said = r.recent('door.rang', 1).single;
    expect(said.cause.by, const Principal('guest', 'ann'));
    final change = r.explain('book.last').change!;
    expect(r.read('book.last'), 'ann');
    expect(change.cause.parent, said.id);
    expect(change.cause.by, const Principal('book').child('book'));
  });
}
