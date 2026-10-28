import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/testing.dart';
import 'package:parlance/view.dart';
import 'package:test/test.dart';

/// A word met at run time is held to the one code was built against
/// (SPEC §6.5, §23.3): by the rule a vocabulary's kept schema is held to,
/// one whose kind or types break a promise is `WordMismatch`, saying
/// where, here and across a connection; one that only adds what a caller
/// may leave out is ready.
typedef Volume = ({int volume});
typedef SetNow = ({int volume, bool? fade});

RecordShape<T> _set<T>(Map<String, Part> fields) => RecordShape<T>(
  fields,
  to: (_) => const {},
  from: (_) => throw UnimplementedError(),
);

/// The words as the guest was built against them.
enum Built<T> implements IStateWord<T> {
  volume<int>('deck.volume', Plain(IntType(min: 0, max: 100))),
  mode<String>('deck.mode', Plain(EnumType(['a', 'b'])));

  const Built(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

enum BuiltCommand<P, R> implements ICommandWord<P, R> {
  set<Volume, void>('deck.set');

  const BuiltCommand(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _built as RecordShape<P>;
  @override
  Shape<R>? get returns => null;
}

final _built = _set<Volume>({'volume': const Part(Plain(IntType()))});

/// The same words as the owner defines them now.
enum Now<T> implements IStateWord<T> {
  volume<int>('deck.volume', Plain(IntType(min: 0, max: 50))),
  mode<String>('deck.mode', Plain(EnumType(['a', 'b'])));

  const Now(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

enum NowCommand<P, R> implements ICommandWord<P, R> {
  set<SetNow, void>('deck.set');

  const NowCommand(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _now as RecordShape<P>;
  @override
  Shape<R>? get returns => null;
}

/// A param added that a caller may leave out: every call made before
/// still passes.
final _now = _set<SetNow>({
  'volume': const Part(Plain(IntType())),
  'fade': const Part(Plain(BoolType()), optional: true),
});

const deck = Principal('deck');
const guest = Principal('widlet', 'b');
const anyone = Callers({'*': Access.allow});

void main() {
  late TestHost host;

  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  void defineNow() {
    final p = host.participant(deck, vocabularies: [WordSet.open('deck')]);
    p.state(Now.volume).define();
    p.state(Now.mode).define();
    p.command(NowCommand.set).define((_) {}, callers: anyone);
  }

  for (final across in [false, true]) {
    group(across ? 'across a connection' : 'in this process', () {
      Future<IParticipant> asGuest() async {
        if (!across) return host.participant(guest);
        final p = await host.join(guest);
        await p.settle();
        return p;
      }

      test(
        'a type that breaks a promise is a mismatch, saying where',
        () async {
          defineNow();
          final b = await asGuest();
          await b.settle();
          expect(
            b.state(Built.volume).status,
            const WordMismatch(['type.max: was 100, is 50']),
          );
          expect(b.state(Built.mode).status, const WordReady());
          expect(
            b.status('deck.volume'),
            const WordReady(),
            reason: 'by name there is no type to hold it to',
          );
        },
      );

      test('a param added that may be left out keeps every promise', () async {
        defineNow();
        final b = await asGuest();
        await b.settle();
        expect(b.command(BuiltCommand.set).status, const WordReady());
      });

      test('the words a part was built against, checked at once', () async {
        defineNow();
        final b = await asGuest();
        await b.settle();
        expect(wordMismatches(b, [...Built.values, ...BuiltCommand.values]), {
          'deck.volume': ['type.max: was 100, is 50'],
        });
      });

      test(
        'a word that comes later is told a mismatch when it comes',
        () async {
          final b = await asGuest();
          final seen = <WordStatus>[];
          final sub = b.state(Built.volume).statusChanges.listen(seen.add);
          await pumpEventQueue();
          defineNow();
          await b.settle();
          await pumpEventQueue();
          expect(seen.first, const WordMissing());
          expect(seen.last, isA<WordMismatch>());
          await sub.cancel();
        },
      );
    });
  }
}
