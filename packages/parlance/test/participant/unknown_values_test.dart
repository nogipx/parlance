import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/compat.dart'
    show schemaOfDescriptor, schemaOfWord;
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

/// An enum value or a variant added after code was built (SPEC §25.2):
/// code that has a fallback for it reads on; code with none reads none
/// rather than throw, and the registry tells the break certain once a
/// value meets it.
enum Mode { a, b }

enum ModeOr { a, b, other }

final class S<T> implements IStateWord<T> {
  const S(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

final class F<T> implements IFactWord<T> {
  const F(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

final class Q<R> implements IQueryWord<(), R> {
  const Q(this.name, this.returns);
  @override
  final String name;
  @override
  RecordShape<()> get params => RecordShape.none;
  @override
  final Shape<R> returns;
}

const abc = EnumType(['a', 'b', 'c']);
const builtMode = S('deck.mode', EnumShape(Mode.values));
const nowMode = S<String>('deck.mode', PlainShape(abc));
const builtSaid = F('deck.said', EnumShape(Mode.values));
const nowSaid = F<String>('deck.said', PlainShape(abc));
const builtPick = Q('deck.pick', EnumShape(Mode.values));
const nowPick = Q<String>('deck.pick', PlainShape(abc));

sealed class Pet {
  const Pet();
}

final class Cat extends Pet {
  const Cat();
}

final class UnknownPet extends Pet {
  const UnknownPet(this.json);
  final Map<String, Object?> json;
}

final pets = UnionShape<Pet>(
  'is',
  {'cat': RecordShape<Pet>({}, to: (_) => {}, from: (_) => const Cat())},
  tagOf: (p) => p is Cat ? 'cat' : 'unknown',
  unknown: UnknownPet.new,
);

typedef Turn = ({int volume});

/// The turn as code reads it: the volume needed.
final builtTurn = S(
  'deck.turn',
  RecordShape<Turn>(
    {'volume': const Part(PlainShape(IntType()))},
    to: (t) => {'volume': t.volume},
    from: (m) => (volume: m['volume']! as int),
  ),
);

/// The turn as its owner writes it now: the volume may be left out.
const nowTurn = S<Object?>(
  'deck.turn',
  PlainShape(RecordType({'volume': Field(IntType(), optional: true)})),
);

/// A class read by its own fromJson, as json_serializable's are.
final class Box {
  const Box(this.n);
  factory Box.fromJson(Map<String, Object?> m) => Box(m['n']! as int);
  final int n;
  Map<String, Object?> toJson() => {'n': n};
}

final builtBox = S(
  'deck.box',
  JsonShape<Box>(
    Box.fromJson,
    (b) => b.toJson(),
    type: const RecordType({'n': Field(IntType())}),
  ),
);
const nowBox = S<Object?>(
  'deck.box',
  PlainShape(RecordType({'n': Field(TextType())})),
);

const deck = Principal('deck');
const guest = Principal('widlet', 'b');
const possible = WordBreak(
  'type.values',
  BreakKind.value,
  ['a', 'b'],
  ['a', 'b', 'c'],
  certain: false,
);

void main() {
  group('what code reads', () {
    test('an enum value it does not know reads as its fallback', () {
      const shape = EnumShape(ModeOr.values, unknown: ModeOr.other);
      expect(shape.fromJson('c'), ModeOr.other);
      expect(shape.fromJson('a'), ModeOr.a);
      expect(shape.type.toJson()['unknown'], 'other');
    });

    test('with no fallback, it is an UnknownValue', () {
      expect(
        () => const EnumShape(Mode.values).fromJson('c'),
        throwsA(
          isA<UnknownValue>().having((e) => e.value, 'value', 'c').having(
            (e) => e.known,
            'known',
            ['a', 'b'],
          ),
        ),
      );
      expect(
        () => UnionShape<Pet>(
          'is',
          const {},
          tagOf: (_) => '',
        ).fromJson({'is': 'dog'}),
        throwsA(isA<UnknownValue>()),
      );
    });

    test('a variant it does not know reads as what its fallback makes, '
        'the JSON kept', () {
      final dog = pets.fromJson({'is': 'dog', 'barks': true});
      expect(dog, isA<UnknownPet>());
      expect((dog as UnknownPet).json, {'is': 'dog', 'barks': true});
      expect(pets.type.toJson()['unknown'], true);
    });
  });

  group('the rule', () {
    Map<String, Object?> stateOf(ValueType<Object?> t) =>
        schemaOfDescriptor(StateDescriptor('deck.mode', type: t));

    test('a value added breaks no code that has a fallback for it', () {
      final now = stateOf(abc);
      expect(
        entryBreaks(
          schemaOfWord(
            const S('deck.mode', EnumShape(ModeOr.values, unknown: ModeOr.a)),
          ),
          now,
        ).where((b) => b.kind == BreakKind.value),
        isEmpty,
      );
      expect(entryBreaks(schemaOfWord(builtMode), now), [possible]);
      expect(
        entryBreaks(
          schemaOfWord(S('deck.pets', pets)),
          schemaOfDescriptor(
            StateDescriptor(
              'deck.pets',
              type: UnionType('is', {
                'cat': const RecordType({}),
                'dog': const RecordType({}),
              }),
            ),
          ),
        ),
        isEmpty,
      );
    });

    test('what code gives is held to what the registry takes, whatever '
        'the owner falls back to', () {
      Map<String, Object?> command(Map<String, Object?> mode) => {
        'is': 'command',
        'params': {
          'type': 'object',
          'fields': {
            'mode': {'type': mode},
          },
        },
      };
      expect(
        entryBreaks(
          command(abc.toJson()),
          command(const EnumType(['a', 'b'], unknown: 'a').toJson()),
        ),
        hasLength(1),
      );
    });
  });

  late TestHost host;
  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  IRawParticipant owner() =>
      host.participant(deck, vocabularies: [WordSet.open('deck')]).raw;

  for (final across in [false, true]) {
    group(across ? 'across a connection' : 'in this process', () {
      Future<IParticipant> asGuest() async {
        if (!across) return host.participant(guest);
        final p = await host.join(guest);
        await p.settle();
        return p;
      }

      test('a typed read of a value its code does not know gives none, '
          'and does not throw', () async {
        final errors = <ParticipantError>[];
        owner().state(nowMode).define().set('c');
        final b = await asGuest();
        if (b is RemoteParticipant) b.errors.listen(errors.add);
        final seen = <Mode?>[];
        final sub = b.raw
            .watchAs('deck.mode', builtMode.shape)
            .listen(seen.add);
        await b.raw.fetch('deck.mode');
        await pumpEventQueue();
        expect(b.raw.readAs('deck.mode', builtMode.shape), isNull);
        expect(b.raw.read('deck.mode'), 'c', reason: 'its JSON is there');
        expect(seen, [null]);
        await sub.cancel();
        if (across) {
          expect(
            errors.single.code,
            ParticipantErrorCode.unreadable,
            reason: 'told once',
          );
          expect(errors.single.why, contains('deck.mode'));
        }
      });

      test('a value missing a field its code needs, or its class cannot '
          'read, gives none too, told once a word', () async {
        final errors = <ParticipantError>[];
        final o = owner();
        o.state(nowTurn).define().set(const <String, Object?>{});
        o.state(nowBox).define().set(const {'n': 'x'});
        final b = await asGuest();
        if (b is RemoteParticipant) b.errors.listen(errors.add);
        await b.raw.fetch('deck.turn');
        await b.raw.fetch('deck.box');
        await pumpEventQueue();
        expect(b.raw.readAs('deck.turn', builtTurn.shape), isNull);
        expect(b.raw.readAs('deck.box', builtBox.shape), isNull);
        expect(b.raw.readAs('deck.box', builtBox.shape), isNull);
        if (across) {
          expect(
            [for (final e in errors) e.op['word']],
            ['deck.turn', 'deck.box'],
          );
          expect(
            {for (final e in errors) e.code},
            {ParticipantErrorCode.unreadable},
          );
        }
      });

      test('a fact holding a value its code does not know is not heard; '
          'the next one is', () async {
        final say = owner().fact(nowSaid).define();
        final b = await asGuest();
        final heard = <Mode>[];
        final sub = b.raw.factsAs('deck.said', builtSaid.shape).listen((f) {
          heard.add(f.$1);
        });
        await b.settle();
        await pumpEventQueue();
        say
          ..say('c')
          ..say('a');
        await pumpEventQueue();
        if (b is RemoteParticipant) await b.settle();
        await pumpEventQueue();
        expect(heard, [Mode.a]);
        await sub.cancel();
      });
    });
  }

  group('a possible break, met', () {
    test('is told certain once a value written meets it', () async {
      final told = <Mismatch>[];
      host.registry.mismatchChanges.listen(told.add);
      final b = host.participant(guest)..raw.builtAgainst([builtMode]);
      final mode = owner().state(nowMode).define();
      await pumpEventQueue();
      expect(host.registry.mismatches.single.breaks, [possible]);
      mode.set('b');
      await pumpEventQueue();
      expect(host.registry.mismatches.single.breaks.single.certain, isFalse);
      mode.set('c');
      await pumpEventQueue();
      expect(host.registry.mismatches.single.breaks.single.certain, isTrue);
      expect(told.last.breaks.single.certain, isTrue);
      expect(b.raw.readAs('deck.mode', builtMode.shape), isNull);
    });

    test('deep in what is written: a field of an item of a list', () async {
      ValueType<Object?> queue(EnumType mode) =>
          ListType(RecordType({'mode': Field(mode)}));
      host.participant(guest).raw.builtAgainst([
        S('deck.queue', PlainShape(queue(const EnumType(['a', 'b'])))),
      ]);
      final q = owner().state(S<Object?>('deck.queue', PlainShape(queue(abc))));
      final w = q.define();
      await pumpEventQueue();
      expect(
        host.registry.mismatches.single.breaks.single.path,
        'type.item.fields.mode.type.values',
      );
      w.set([
        {'mode': 'a'},
      ]);
      await pumpEventQueue();
      expect(host.registry.mismatches.single.breaks.single.certain, isFalse);
      w.set([
        {'mode': 'a'},
        {'mode': 'c'},
      ]);
      await pumpEventQueue();
      expect(host.registry.mismatches.single.breaks.single.certain, isTrue);
    });

    test('a needed field left out, once a value lacks it', () async {
      host.participant(guest).raw.builtAgainst([builtTurn]);
      final turn = owner().state(nowTurn).define();
      await pumpEventQueue();
      final only = host.registry.mismatches.single.breaks.single;
      expect(only.path, 'type.fields.volume');
      expect(only.certain, isFalse);
      turn.set(const {'volume': 1});
      await pumpEventQueue();
      expect(host.registry.mismatches.single.breaks.single.certain, isFalse);
      turn.set(const <String, Object?>{});
      await pumpEventQueue();
      expect(host.registry.mismatches.single.breaks.single.certain, isTrue);
    });

    test('by a fact said', () async {
      host.participant(guest).raw.builtAgainst([builtSaid]);
      final say = owner().fact(nowSaid).define();
      await pumpEventQueue();
      say.say('a');
      await pumpEventQueue();
      expect(host.registry.mismatches.single.breaks.single.certain, isFalse);
      say.say('c');
      await pumpEventQueue();
      expect(host.registry.mismatches.single.breaks.single.certain, isTrue);
    });

    test('by an answer, to the one who asked only', () async {
      final b = host.participant(guest)..raw.builtAgainst([builtPick]);
      const other = Principal('widlet', 'c');
      final c = host.participant(other)..raw.builtAgainst([builtPick]);
      owner().query(nowPick).define((_) => 'c');
      await pumpEventQueue();
      final answer = await b.raw.query(builtPick).ask(());
      expect(answer, isA<CallFailed>(), reason: 'its code cannot read it');
      final byWho = {
        for (final m in host.registry.mismatches) m.by: m.breaks.single.certain,
      };
      expect(byWho, {guest: true, other: false});
      c.dispose();
    });
  });
}
