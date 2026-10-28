import 'dart:async';

import 'package:parlance/core.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';
import 'package:parlance/src/registry/words.dart' show TypedRegistry;

/// Code written against the core's interfaces (SPEC §21.6) runs the same on
/// local states, commands and facts and on the registry's typed words: moving from
/// one to the other changes only where they are made.
void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('on the core', () async {
    final count = LocalState<int>();
    final doubled = LocalCommand<Double, int>()..serve((p) => p.n * 2);
    final said = LocalFact<String>();
    final feature = Counter(
      count: count,
      write: count.claim(),
      double: doubled,
      say: said.claim(),
      heard: said,
    );

    expect(await feature.run(), [21, 42, 'doubled to 42']);
    await settle();
    expect(feature.log, ['doubled to 42']);
    await feature.dispose();
  });

  test('on the registry', () async {
    final r = Registry();
    const owner = Principal('owner');
    final writer = r.state(CounterState.count).define(by: owner);
    r
        .command(CounterCommand.double)
        .define((c) => c.params.n * 2, callers: Callers.only(['owner']));
    final feature = Counter(
      count: r.state(CounterState.count).reader(),
      write: writer,
      double: r.command(CounterCommand.double).caller(by: owner),
      say: r.fact(CounterFact.said).define(by: owner),
      heard: r.fact(CounterFact.said).listener,
    );

    expect(await feature.run(), [21, 42, 'doubled to 42']);
    await settle();
    expect(feature.log, ['doubled to 42']);
    await feature.dispose();
    await r.dispose();
  });

  test('a refused call fails with how it ended', () async {
    final r = Registry();
    r
        .command(CounterCommand.double)
        .define((c) => c.params.n * 2, callers: Callers.only(['owner']));
    final ask = r
        .command(CounterCommand.double)
        .caller(by: const Principal('guest'));
    await expectLater(
      ask.call((n: 1)),
      throwsA(
        isA<CallNotDone>().having(
          (e) => e.result,
          'result',
          isA<CallRefused>(),
        ),
      ),
    );
    await r.dispose();
  });
}

/// A feature that knows only the interfaces.
final class Counter {
  Counter({
    required this.count,
    required this.write,
    required this.double,
    required this.say,
    required IFactListener<String> heard,
  }) {
    _sub = heard.stream.listen(log.add);
  }

  final IStateReader<int> count;
  final IStateWriter<int> write;
  final ICommandCaller<Double, int> double;
  final IFactEmitter<String> say;
  final List<String> log = [];
  late final StreamSubscription<String> _sub;

  Future<List<Object?>> run() async {
    write.set(21);
    final before = count.value;
    final after = await double.call((n: before!));
    write.set(after);
    say.emit('doubled to $after');
    return [before, count.value, 'doubled to $after'];
  }

  Future<void> dispose() => _sub.cancel();
}

enum CounterState<T> implements IStateWord<T> {
  count<int>('counter.count', Plain(IntType()));

  const CounterState(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

typedef Double = ({int n});

const _double = RecordShape<Double>(
  {'n': Part(Plain(IntType()))},
  to: _doubleTo,
  from: _doubleFrom,
);
Map<String, Object?> _doubleTo(Double d) => {'n': d.n};
Double _doubleFrom(Map<String, Object?> m) => (n: m['n']! as int);

enum CounterCommand<P, R> implements ICommandWord<P, R> {
  double<Double, int>('counter.double', _double, returns: Plain(IntType()));

  const CounterCommand(this.name, this.params, {this.returns});
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

enum CounterFact<T> implements IFactWord<T> {
  said<String>('counter.said', Plain(TextType()));

  const CounterFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}
