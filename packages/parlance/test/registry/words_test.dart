import 'package:parlance/registry.dart';
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
  {'apps': Part(Nullable(ListShape(Plain(TextType()))))},
  to: _onlyTo,
  from: _onlyFrom,
);
Map<String, Object?> _onlyTo(Only o) => {'apps': o.apps};
Only _onlyFrom(Map<String, Object?> m) => (apps: m['apps'] as List<String>?);

/// None is a value of its own: every app, apart from none of them.
enum NullableState<T> implements IStateWord<T> {
  only<List<String>?>('test.only', Nullable(ListShape(Plain(TextType()))));

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

  test('a nullable state is held over none, and none comes back', () async {
    final only = f.r.state(NullableState.only).define(by: owner);
    only.set(null);
    f.r
        .command(NullableCommand.setOnly)
        .define(
          (c) => only.set(c.params.apps, cause: c.causeFor(owner)),
          callers: Callers.only(['user', 'system']),
          sets: const Sets('test.only', value: 'apps'),
        );
    expect(f.r.has('test.only'), isTrue);
    f.r.pushLayer(
      'test.only',
      value: ['iina'],
      owner: 'scene',
      by: Principal.system,
    );
    await pumpEventQueue();
    expect(f.r.state(NullableState.only).read(), ['iina']);
    f.r.dropLayersOf('scene');
    await pumpEventQueue();
    expect(f.r.has('test.only'), isTrue);
    expect(f.r.state(NullableState.only).read(), isNull);
    expect(
      await f.r.command(NullableCommand.setOnly).call((apps: []), by: user),
      isA<CallDone<void>>(),
    );
    expect(f.r.state(NullableState.only).read(), isEmpty);
    // A typed call says null: every app again.
    expect(_only.toJson((apps: null)), {'apps': null});
    expect(
      await f.r.command(NullableCommand.setOnly).call((apps: null), by: user),
      isA<CallDone<void>>(),
    );
    expect(f.r.state(NullableState.only).read(), isNull);
  });
}
