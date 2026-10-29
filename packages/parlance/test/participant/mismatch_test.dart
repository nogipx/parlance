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
typedef VolumeNow = ({int volume, bool? fade});

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

/// The same words as the owner defines them now: the volume may go
/// higher than the code built against it reads.
enum Now<T> implements IStateWord<T> {
  volume<int>('deck.volume', Plain(IntType(min: 0, max: 150))),
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
  set<VolumeNow, void>('deck.set');

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
final _now = _set<VolumeNow>({
  'volume': const Part(Plain(IntType())),
  'fade': const Part(Plain(BoolType()), optional: true),
});

/// The volume as another owner defines it: all of it changed.
enum Wide<T> implements IStateWord<T> {
  volume<num>('deck.volume', Plain(NumType(min: -1)));

  const Wide(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

/// The command with a param added that may be left out, and the one it
/// had turned to text.
enum BrokenCommand<P, R> implements ICommandWord<P, R> {
  set<VolumeNow, void>('deck.set');

  const BrokenCommand(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _broken as RecordShape<P>;
  @override
  Shape<R>? get returns => null;
}

final _broken = _set<VolumeNow>({
  'volume': const Part(Plain(TextType())),
  'fade': const Part(Plain(BoolType()), optional: true),
});

/// Each break a status says, as text; none for one that is no mismatch.
List<String> said(WordStatus s) => [
  if (s case WordMismatch(:final breaks))
    for (final b in breaks) '$b',
];

const deck = Principal('deck');
const guest = Principal('widlet', 'b');
const anyone = Callers({'*': Access.allow});

void main() {
  late TestHost host;

  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  void defineNow() {
    final p = host.participant(deck, vocabularies: [WordSet.open('deck')]);
    p.raw.state(Now.volume).define();
    p.raw.state(Now.mode).define();
    p.raw.command(NowCommand.set).define((_) {}, callers: anyone);
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
          expect(said(b.raw.state(Built.volume).status), [
            'type.max: was 100, is 150',
          ]);
          expect(b.raw.state(Built.mode).status, const WordReady());
          expect(
            b.raw.status('deck.volume'),
            const WordReady(),
            reason: 'by name there is no type to hold it to',
          );
        },
      );

      test('every difference is told, at once', () async {
        final p = host.participant(deck, vocabularies: [WordSet.open('deck')]);
        p.raw.state(Wide.volume).define();
        final b = await asGuest();
        await b.settle();
        expect(said(b.raw.state(Built.volume).status), [
          'type.type: was int, is num',
        ], reason: 'a type changed says no bound of it');
      });

      test('a param added beside a break is no break of its own', () async {
        final p = host.participant(deck, vocabularies: [WordSet.open('deck')]);
        p.raw.command(BrokenCommand.set).define((_) {}, callers: anyone);
        final b = await asGuest();
        await b.settle();
        expect(said(b.raw.command(BuiltCommand.set).status), [
          'params.fields.volume.type.type: was int, is text',
        ]);
      });

      test('a param added that may be left out keeps every promise', () async {
        defineNow();
        final b = await asGuest();
        await b.settle();
        expect(b.raw.command(BuiltCommand.set).status, const WordReady());
      });

      test('the words a part was built against, checked at once', () async {
        defineNow();
        final b = await asGuest();
        await b.settle();
        expect(
          wordMismatches(b.raw, [
            ...Built.values,
            ...BuiltCommand.values,
          ]).map((w, breaks) => MapEntry(w, [for (final x in breaks) '$x'])),
          {
            'deck.volume': ['type.max: was 100, is 150'],
          },
        );
      });

      test(
        'a word that comes later is told a mismatch when it comes',
        () async {
          final b = await asGuest();
          final seen = <WordStatus>[];
          final sub = b.raw.state(Built.volume).statusChanges.listen(seen.add);
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
