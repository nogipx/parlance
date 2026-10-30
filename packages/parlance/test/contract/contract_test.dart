import 'package:parlance/app.dart';
import 'package:test/test.dart';

/// The behaviour the frozen libraries promise (docs/план-api.md, Г): what
/// an app may build on and no release changes. Written with `app.dart`
/// alone, so what they need is what a developer is given; what they
/// watch of the registry to tell, through its tools (`Host.registry`).
enum _State<T> implements IStateWord<T> {
  level<int>('deck.level', Plain(IntType(min: 0, max: 100)));

  const _State(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

enum _Command<P, R> implements ICommandWord<P, R> {
  set<({int to}), int>('deck.set', _to, Plain(IntType()));

  const _Command(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

const _to = RecordShape<({int to})>(
  {'to': Part(Plain(IntType(min: 0, max: 100)))},
  to: _toJson,
  from: _fromJson,
);
Map<String, Object?> _toJson(({int to}) p) => {'to': p.to};
({int to}) _fromJson(Map<String, Object?> m) => (to: m['to']! as int);

final class _Deck implements IOwner {
  _Deck() {
    IOwner.made(this, define: _define);
  }

  late final IStateWriterOf<int> level;
  var served = 0;

  void _define(IParticipant p) {
    level = GeneratedWords.of(p).state(_State.level).define();
    GeneratedWords.of(p).command(_Command.set).serve((x) {
      served++;
      level.set(x.to);
      return x.to;
    }, callers: const Callers({'user': Access.allow}));
  }
}

void main() {
  late Host r;
  late _Deck deck;
  late IParticipant user;
  setUp(() async {
    r = Host();
    deck = _Deck();
    r.participant(
      const Principal('deck'),
      vocabularies: [WordSet.open('deck')],
      owners: [deck],
    );
    user = r.participant(const Principal('user', 'ann'));
  });
  tearDown(() => r.dispose());

  test('contract: a command\'s handler runs once for a call id; the same '
      'id answers its first result', () async {
    final first = await GeneratedWords.of(
      user,
    ).command(_Command.set).call((to: 7), id: 'c1');
    final again = await GeneratedWords.of(
      user,
    ).command(_Command.set).call((to: 7), id: 'c1');
    expect((first as CallDone<int>).value, 7);
    expect((again as CallDone<int>).value, 7);
    expect(deck.served, 1);
  });

  test('contract: a refusal says why, and nothing runs', () async {
    final guest = r.participant(const Principal('guest', 'bob'));
    final r1 = await GeneratedWords.of(
      guest,
    ).command(_Command.set).call((to: 1));
    expect(r1, isA<CallRefused>());
    expect(r1.why, isNotEmpty);
    final r2 = await GeneratedWords.of(
      user,
    ).command(_Command.set).call((to: 500));
    expect(r2, isA<CallRefused>(), reason: 'out of its range');
    expect(deck.served, 0);
  });

  test('contract: a write equal to what is kept makes no change', () async {
    deck.level.set(5);
    await user.settle();
    var ticks = 0;
    final sub = r.registry.ticks.listen((_) => ticks++);
    deck.level.set(5);
    await user.settle();
    await sub.cancel();
    expect(ticks, 0);
  });

  test('contract: a batch is whole or nothing', () async {
    deck.level.set(1);
    expect(
      () => deck.batch(() {
        deck.level.set(2);
        throw StateError('no');
      }),
      throwsStateError,
    );
    await user.settle();
    expect(GeneratedWords.of(user).state(_State.level).read(), 1);
  });

  test('contract: what a handler writes follows from its call', () async {
    await GeneratedWords.of(user).command(_Command.set).call((to: 9), id: 'c9');
    expect(r.registry.explain('deck.level').change!.cause.parent, 'c9');
  });

  test(
    'contract: a participant gone, its words are missing to everyone',
    () async {
      final p = r.participant(
        const Principal('lamp'),
        vocabularies: [WordSet.open('lamp')],
      );
      GeneratedWords.of(p).state(const _Lamp()).define();
      expect(GeneratedWords.of(user).status(const _Lamp()), isA<WordReady>());
      p.dispose();
      expect(GeneratedWords.of(user).status(const _Lamp()), isA<WordMissing>());
    },
  );
}

final class _Lamp implements IStateWord<bool> {
  const _Lamp();
  @override
  String get name => 'lamp.on';
  @override
  Shape<bool> get shape => const Plain(BoolType());
  @override
  String? get key => null;
}
