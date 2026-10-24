import 'package:switchboard/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

enum Level { low, high }

typedef Tune = ({String input, num db, Level? level});

const _tune = RecordShape<Tune>(
  {
    'input': Part(Plain(RefType('input'))),
    'db': Part(Plain(NumType(min: -60, max: 12))),
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
  {'inputs': Part(ListShape(Plain(TextType())))},
  to: _heardTo,
  from: _heardFrom,
);
Map<String, Object?> _heardTo(Heard h) => {'inputs': h.inputs};
Heard _heardFrom(Map<String, Object?> m) =>
    (inputs: m['inputs']! as List<String>);

/// A host's words as an enum: the name and the types once.
enum TestState<T> implements StateWord<T> {
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

enum TestCommand<P, R> implements CommandWord<P, R> {
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

enum TestFact<T> implements FactWord<T> {
  tuned<Tune>('test.tuned', _tune);

  const TestFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

void main() {
  late Fixture f;
  late StateWriterOf<Tune> tune;
  late FactEmitterOf<Tune> tuned;
  setUp(() {
    f = Fixture();
    f.r.state(TestState.level).define(by: owner);
    tune = f.r.state(TestState.tune).define(by: owner);
    tuned = f.r.fact(TestFact.tuned).define(by: owner);
    f.r.command(TestCommand.tune).define((c) {
      tune.set(c.params, key: c.params.input, cause: c.causeFor(owner));
      tuned.emit(c.params, cause: c.causeFor(owner));
      return (inputs: [c.params.input]);
    }, callers: Callers.only(['user']));
    f.r
        .command(TestCommand.reset)
        .define((c) {}, callers: Callers.only(['user']));
  });
  tearDown(() => f.r.dispose());

  test(
    'a typed call goes in as JSON and its answer comes back typed',
    () async {
      final r = await f.r.command(TestCommand.tune).call((
        input: 'mic',
        db: -6,
        level: Level.high,
      ), by: user);
      expect((r as CallDone<Heard>).value.inputs, ['mic']);
      expect(f.r.read('test.tune', key: 'mic'), {
        'input': 'mic',
        'db': -6,
        'level': 'high',
      });
      expect(f.r.state(TestState.tune).read(key: 'mic')?.level, Level.high);
    },
  );

  test('what is wrong is refused as by name, typed for any answer', () async {
    final r = await f.r.command(TestCommand.tune).call((
      input: 'nope',
      db: 0,
      level: null,
    ), by: user);
    expect(
      r,
      isA<CallRefused>().having((x) => x.code, 'code', Refusal.invalidParams),
    );
    expect(
      await f.r.command(TestCommand.reset).call((), by: viewer),
      isA<CallRefused>(),
    );
    expect(
      await f.r.command(TestCommand.reset).call((), by: user),
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
    expect(d.returns, isA<ObjectType>());
  });

  test('states and facts read and stream typed', () async {
    final facts = <Fact<Tune>>[];
    f.r.fact(TestFact.tuned).stream.listen(facts.add);
    final levels = <Level?>[];
    f.r.state(TestState.level).watch().listen(levels.add);
    await f.r.command(TestCommand.tune).call((
      input: 'mic',
      db: 3,
      level: null,
    ), by: user);
    await pumpEventQueue();
    expect(facts.single.payload, (input: 'mic', db: 3, level: null));
    expect(facts.single.cause.parent, isNotNull);
    expect(f.r.fact(TestFact.tuned).recent().single.payload.db, 3);
    expect(levels, [null]);
    expect(f.r.state(TestState.tune).readAll().keys, ['mic']);
  });
}
