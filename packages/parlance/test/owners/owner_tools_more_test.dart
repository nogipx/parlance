import 'dart:async';

import 'package:clock/clock.dart';
import 'package:parlance/app.dart';
import 'package:test/test.dart';
import 'package:parlance/tools.dart' show StateWordOf;
import 'package:parlance/testing.dart';

/// What an owner says with the tools beside its words (SPEC §19): a guard
/// of its own command by its params, the time by the registry's clock,
/// a word named at run time, and a command's status that follows what it
/// heard, with no one telling the registry so.
const _to = RecordShape<({int to})>(
  {'to': Part(Plain(IntType()))},
  to: _toJson,
  from: _fromJson,
);
Map<String, Object?> _toJson(({int to}) p) => {'to': p.to};
({int to}) _fromJson(Map<String, Object?> m) => (to: m['to']! as int);

enum _Command<P, R> implements ICommandWord<P, R> {
  set<({int to}), void>('dial.set', _to, null);

  const _Command(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

final class _Dial implements IOwner {
  _Dial(Stream<bool> power) {
    IOwner.made(this, define: _define);
    guard(
      _Command.set,
      'gentle',
      (p, by) => p.to > 10 && by.kind != 'admin' ? 'too far for $by' : null,
    );
    listen(power, (on) => this.on = on);
    whenAttached(
      (p) => GeneratedWords.of(p)
          .state(StateWordOf<int>('dial.$serial', const Plain(IntType())))
          .define()
          .set(7),
    );
  }

  final String serial = 'x1';
  var on = true;
  int? at;

  void _define(IParticipant p) {
    GeneratedWords.of(p)
        .command(_Command.set)
        .serve(
          (x) => at = x.to,
          callers: const Callers({'*': Access.allow}),
          available: () => on ? null : 'it is off',
        );
  }
}

/// An owner of no words: a rule of the whole participant.
final class _NoAgents implements IOwner {
  _NoAgents() {
    IOwner.made(this, define: (_) {});
    guardAll(
      'no-agents',
      (command, by) => by.kind == 'agent' ? 'no agent calls $command' : null,
    );
  }
}

enum _Fact<T> implements IFactWord<T> {
  rang<String>('bell.rang', Plain(TextType()));

  const _Fact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

final class _Bell implements IOwner {
  _Bell() {
    IOwner.made(
      this,
      define: (p) => _rang = GeneratedWords.of(p).fact(_Fact.rang).define(),
    );
  }

  late IFactEmitterOf<String> _rang;

  /// A ring from outside, which may come twice.
  bool ring(String id, String who) => once(id, () => _rang.emit(who));
}

enum _Lit<T> implements IStateWord<T> {
  of<bool>('lamps.lit', Plain(BoolType()));

  const _Lit(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => 'bulb';
}

const _bulb = RecordShape<({String bulb})>(
  {'bulb': Part(Plain(ChoiceType('bulb')))},
  to: _bulbJson,
  from: _fromBulb,
);
Map<String, Object?> _bulbJson(({String bulb}) p) => {'bulb': p.bulb};
({String bulb}) _fromBulb(Map<String, Object?> m) =>
    (bulb: m['bulb']! as String);

enum _Drop<P, R> implements ICommandWord<P, R> {
  of<({String bulb}), void>('lamps.drop', _bulb, null);

  const _Drop(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// Lamps of bulbs: which are lit, by bulb; a bulb dropped goes of them by
/// itself, as a choice and as a key.
final class _Lamps implements IOwner {
  _Lamps({this.listed = true}) {
    IOwner.made(
      this,
      define: (p) {
        Keyed.attach(lit, GeneratedWords.of(p).state(_Lit.of).define());
        GeneratedWords.of(p)
            .command(_Drop.of)
            .serve(
              (x) => bulbs.remove(x.bulb),
              callers: const Callers({'*': Access.allow}),
            );
      },
    );
    if (listed) choices('bulb', () => [for (final b in bulbs) Choice(b)]);
    follow(() {
      for (final b in bulbs) {
        lit[b] = true;
      }
    });
  }

  final bool listed;
  final List<String> bulbs = ['a', 'b'];
  final Keyed<bool> lit = Keyed<bool>();
}

void main() {
  test('a choice that went goes of the keyed states by its kind, with '
      'no one removing it', () async {
    final r = Host();
    addTearDown(r.dispose);
    final lamps = _Lamps();
    await r
        .participant(
          const Principal('lamps'),
          vocabularies: [WordSet.open('lamps')],
        )
        .attach({'it': lamps});
    final ann = r.participant(const Principal('user', 'ann'));
    expect(GeneratedWords.of(ann).state(_Lit.of).readAll().keys, {'a', 'b'});

    expect(
      await GeneratedWords.of(ann).command(_Drop.of).call((bulb: 'b')),
      isA<CallDone<void>>(),
    );
    await ann.settle();
    expect(GeneratedWords.of(ann).state(_Lit.of).readAll().keys, {'a'});
    expect(lamps.lit.keys, ['a']);
    final gone = await GeneratedWords.of(
      ann,
    ).command(_Drop.of).call((bulb: 'b'));
    expect(gone.whyNot, contains('no bulb b'));
  });

  test('a ref to choices no one gives says so', () async {
    final r = Host();
    addTearDown(r.dispose);
    await r
        .participant(
          const Principal('lamps'),
          vocabularies: [WordSet.open('lamps')],
        )
        .attach({'it': _Lamps(listed: false)});
    final ann = r.participant(const Principal('user', 'ann'));
    final r1 = await GeneratedWords.of(ann).command(_Drop.of).call((bulb: 'a'));
    expect(r1.whyNot, contains("choices('bulb', ...)"));
  });

  test('a fact said once by its id is said once, however often it '
      'comes', () async {
    final r = Host();
    addTearDown(r.dispose);
    final bell = _Bell();
    await r
        .participant(
          const Principal('bell'),
          vocabularies: [WordSet.open('bell')],
        )
        .attach({'it': bell});
    final heard = <String>[];
    final ann = r.participant(const Principal('user', 'ann'));
    GeneratedWords.of(
      ann,
    ).fact(_Fact.rang).stream.listen((f) => heard.add(f.payload));
    expect(bell.ring('e1', 'bob'), isTrue);
    expect(bell.ring('e1', 'bob'), isFalse);
    expect(bell.ring('e2', 'cat'), isTrue);
    await ann.settle();
    expect(heard, ['bob', 'cat']);
  });

  test('a guard of its own command judges the params and who calls', () async {
    final r = Host();
    addTearDown(r.dispose);
    final power = Stream<bool>.empty();
    await r
        .participant(
          const Principal('dial'),
          vocabularies: [WordSet.open('dial')],
        )
        .attach({'it': _Dial(power)});
    final ann = r.participant(const Principal('user', 'ann'));
    final admin = r.participant(const Principal('admin'));

    expect(
      await GeneratedWords.of(ann).command(_Command.set).call((to: 3)),
      isA<CallDone<void>>(),
    );
    final far = await GeneratedWords.of(
      ann,
    ).command(_Command.set).call((to: 30));
    expect(far, isA<CallRefused>());
    expect(far.whyNot, contains('too far for user/ann'));
    expect(
      await GeneratedWords.of(admin).command(_Command.set).call((to: 30)),
      isA<CallDone<void>>(),
    );
  });

  test('a guard of all the commands of its participant judges those of '
      'the owners beside it too, here and on a guest', () async {
    for (final across in [false, true]) {
      final host = TestHost();
      addTearDown(host.dispose);
      final IParticipant dial = across
          ? await host.join(
              const Principal('dial'),
              vocabularies: [WordSet.open('dial')],
            )
          : host.participant(
              const Principal('dial'),
              vocabularies: [WordSet.open('dial')],
            );
      await dial.attach({
        'it': _Dial(const Stream.empty()),
        'rules': _NoAgents(),
      });
      await host.settle();
      final agent = host.participant(const Principal('agent', 'a'));
      final ann = host.participant(const Principal('user', 'ann'));
      final refused = await GeneratedWords.of(
        agent,
      ).command(_Command.set).call((to: 3));
      expect(refused, isA<CallRefused>(), reason: 'across: $across');
      expect(refused.whyNot, contains('no agent calls dial.set'));
      expect(
        await GeneratedWords.of(ann).command(_Command.set).call((to: 3)),
        isA<CallDone<void>>(),
      );
    }
  });

  test('what it heard moves its command\'s status, unasked', () async {
    final r = Host();
    addTearDown(r.dispose);
    final power = StreamController<bool>();
    await r
        .participant(
          const Principal('dial'),
          vocabularies: [WordSet.open('dial')],
        )
        .attach({'it': _Dial(power.stream)});
    final ann = r.participant(const Principal('user', 'ann'));
    final seen = <WordStatus>[];
    final sub = GeneratedWords.of(
      ann,
    ).command(_Command.set).statusChanges.listen(seen.add);
    await ann.settle();

    power.add(false);
    await ann.settle();
    expect(
      GeneratedWords.of(ann).command(_Command.set).status,
      isA<WordUnavailable>(),
    );
    power.add(true);
    await ann.settle();
    expect(
      GeneratedWords.of(ann).command(_Command.set).status,
      isA<WordReady>(),
    );
    await sub.cancel();
    expect(seen.whereType<WordUnavailable>(), hasLength(1));
  });

  test('a word named at run time is defined as any other', () async {
    final r = Host();
    addTearDown(r.dispose);
    final p = r.participant(
      const Principal('dial'),
      vocabularies: [WordSet.open('dial')],
    );
    await p.attach({'it': _Dial(const Stream.empty())});
    expect(
      GeneratedWords.of(
        p,
      ).state(const StateWordOf<int>('dial.x1', Plain(IntType()))).read(),
      7,
    );
  });

  test('now is the registry\'s clock once attached, the world\'s before', () {
    final then = DateTime.utc(2030, 1, 2);
    final r = Host(clock: Clock.fixed(then));
    addTearDown(r.dispose);
    final dial = _Dial(const Stream.empty());
    expect(dial.now, isNot(then));
    r
        .participant(
          const Principal('dial'),
          vocabularies: [WordSet.open('dial')],
        )
        .attach({'it': dial});
    expect(dial.now, then);
  });
}
