import 'dart:async';

import 'package:clock/clock.dart';
import 'package:parlance/app.dart';
import 'package:test/test.dart';

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
      (p) => keep(
        p
            .state(StateWordOf<int>('dial.$serial', const Plain(IntType())))
            .define(),
      ).set(7),
    );
  }

  final String serial = 'x1';
  var on = true;
  int? at;

  void _define(IParticipant p) {
    keep(
      p
          .command(_Command.set)
          .serve(
            (x) => at = x.to,
            callers: const Callers({'*': Access.allow}),
            available: () => on ? null : 'it is off',
          ),
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
    IOwner.made(this, define: (p) => _rang = keep(p.fact(_Fact.rang).define()));
  }

  late IFactEmitterOf<String> _rang;

  /// A ring from outside, which may come twice.
  bool ring(String id, String who) => once(id, () => _rang.emit(who));
}

void main() {
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
    ann.fact(_Fact.rang).stream.listen((f) => heard.add(f.payload));
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
      await ann.command(_Command.set).call((to: 3)),
      isA<CallDone<void>>(),
    );
    final far = await ann.command(_Command.set).call((to: 30));
    expect(far, isA<CallRefused>());
    expect(far.whyNot, contains('too far for user/ann'));
    expect(
      await admin.command(_Command.set).call((to: 30)),
      isA<CallDone<void>>(),
    );
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
    final sub = ann.command(_Command.set).statusChanges.listen(seen.add);
    await ann.settle();

    power.add(false);
    await ann.settle();
    expect(ann.command(_Command.set).status, isA<WordUnavailable>());
    power.add(true);
    await ann.settle();
    expect(ann.command(_Command.set).status, isA<WordReady>());
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
    expect(p.read('dial.x1'), 7);
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
