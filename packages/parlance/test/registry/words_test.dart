import 'package:parlance/tools.dart';
import 'package:test/test.dart';

import 'fixture.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

enum Level { low, high }

typedef Tune = ({String input, num db, Level? level});

const _tune = RecordShape<Tune>(
  {
    'input': Part(PlainShape(ChoiceType('input'))),
    'db': Part(PlainShape(NumType(min: -60, max: 12))),
    'level': Part(EnumShape(Level.values), optional: true),
  },
  to: _tuneTo,
  from: _tuneFrom,
);
Map<String, Object?> _tuneTo(Tune t) => {
  'input': t.input,
  'db': t.db,
  'level': t.level,
};
Tune _tuneFrom(Map<String, Object?> m) => (
  input: m['input']! as String,
  db: m['db']! as num,
  level: m['level'] as Level?,
);

typedef Heard = ({List<String> inputs});

const _heard = RecordShape<Heard>(
  {'inputs': Part(ListShape(PlainShape(TextType())))},
  to: _heardTo,
  from: _heardFrom,
);
Map<String, Object?> _heardTo(Heard h) => {'inputs': h.inputs};
Heard _heardFrom(Map<String, Object?> m) =>
    (inputs: m['inputs']! as List<String>);

/// A host's words as an enum: the name and the types once.
enum TestState<T> implements IStateWord<T> {
  level<Level>('test.level', EnumShape(Level.values)),
  tune<Tune>('test.tune', _tune, key: 'input');

  const TestState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

enum TestCommand<P, R> implements ICommandWord<P, R> {
  tune<Tune, Heard>('test.tune.set', _tune, returns: _heard),
  reset<(), void>('test.reset', RecordShape.none);

  const TestCommand(this.name, this.params, {this.returns});
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

typedef Only = ({List<String>? apps});

const _only = RecordShape<Only>(
  {'apps': Part(NullableShape(ListShape(PlainShape(TextType()))))},
  to: _onlyTo,
  from: _onlyFrom,
);
Map<String, Object?> _onlyTo(Only o) => {'apps': o.apps};
Only _onlyFrom(Map<String, Object?> m) => (apps: m['apps'] as List<String>?);

/// None is a value of its own: every app, apart from none of them.
enum NullableState<T> implements IStateWord<T> {
  only<List<String>?>(
    'test.only',
    NullableShape(ListShape(PlainShape(TextType()))),
  );

  const NullableState(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

enum NullableCommand<P, R> implements ICommandWord<P, R> {
  setOnly<Only, void>('test.only.set', _only);

  const NullableCommand(this.name, this.params);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  Shape<R>? get returns => null;
}

enum TestFact<T> implements IFactWord<T> {
  tuned<Tune>('test.tuned', _tune);

  const TestFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

void main() {
  late Fixture f;
  late GeneratedWords house;
  late GeneratedWords asUser;
  late IStateWriterOf<Tune> tune;
  late IFactSayerOf<Tune> tuned;
  setUp(() {
    f = Fixture();
    house = GeneratedWords(
      f.r.participant(owner, vocabularies: [WordSet.open('test')]),
    );
    asUser = GeneratedWords(f.r.participant(user));
    house.state(TestState.level).define();
    tune = house.state(TestState.tune).define();
    tuned = house.fact(TestFact.tuned).define();
    house.command(TestCommand.tune).serve((params) {
      tune.set(params, key: params.input);
      tuned.say(params);
      return (inputs: [params.input]);
    }, callers: Callers.only(['user']));
    house
        .command(TestCommand.reset)
        .serve((_) {}, callers: Callers.only(['user']));
  });
  tearDown(() => f.r.dispose());

  test(
    'a typed call goes in as JSON and its answer comes back typed',
    () async {
      final r = await asUser.command(TestCommand.tune).call((
        input: 'front',
        db: -6,
        level: Level.high,
      ));
      expect((r as CallDone<Heard>).value.inputs, ['front']);
      expect(f.r.read('test.tune', key: 'front'), {
        'input': 'front',
        'db': -6,
        'level': 'high',
      });
      expect(asUser.keyedOf(TestState.tune).of('front')?.level, Level.high);
    },
  );

  test('what is wrong is refused as by name, typed for any answer', () async {
    final r = await asUser.command(TestCommand.tune).call((
      input: 'nope',
      db: 0,
      level: null,
    ));
    expect(
      r,
      isA<CallRefused>().having((x) => x.code, 'code', Refusal.invalidParams),
    );
    expect(
      await GeneratedWords(
        f.r.participant(visitor),
      ).command(TestCommand.reset).call(()),
      isA<CallRefused>(),
    );
    expect(
      await asUser.command(TestCommand.reset).call(()),
      isA<CallDone<void>>(),
    );
  });

  test('the catalog sees the shapes as types', () {
    final d = f.r.commandDescriptor('test.tune.set')!;
    expect(d.params.fields.keys, ['input', 'db', 'level']);
    expect(d.params.fields['level']!.optional, isTrue);
    expect((d.params.fields['level']!.type as EnumType).values, [
      'low',
      'high',
    ]);
    expect(d.returns, isA<RecordType>());
  });

  test('states and facts read and stream typed', () async {
    final facts = <Fact<Tune>>[];
    asUser.factOf(TestFact.tuned).facts.listen(facts.add);
    final levels = <Level?>[];
    asUser.stateOf(TestState.level).changes.listen(levels.add);
    await asUser.command(TestCommand.tune).call((
      input: 'front',
      db: 3,
      level: null,
    ));
    await pumpEventQueue();
    expect(facts.single.payload, (input: 'front', db: 3, level: null));
    expect(facts.single.cause.parent, isNotNull);
    expect(
      (await asUser.factOf(TestFact.tuned).recent(1)).single.payload.db,
      3,
    );
    expect(levels, [null]);
    expect(asUser.keyedOf(TestState.tune).keys, ['front']);
  });

  test('a nullable state takes none, a list, and none again', () async {
    final only = house.state(NullableState.only).define();
    only.set(null);
    house
        .command(NullableCommand.setOnly)
        .serve(
          (params) => only.set(params.apps),
          callers: Callers.only(['user', 'system']),
        );
    expect(f.r.has('test.only'), isTrue);
    expect(asUser.stateOf(NullableState.only).value, isNull);
    expect(
      await asUser.command(NullableCommand.setOnly).call((apps: [])),
      isA<CallDone<void>>(),
    );
    expect(asUser.stateOf(NullableState.only).value, isEmpty);
    // A typed call says null: every app again.
    expect(_only.toJson((apps: null)), {'apps': null});
    expect(
      await asUser.command(NullableCommand.setOnly).call((apps: null)),
      isA<CallDone<void>>(),
    );
    expect(asUser.stateOf(NullableState.only).value, isNull);
  });
}
