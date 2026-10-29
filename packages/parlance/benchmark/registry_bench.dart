/// What the registry's JSON costs over the core, which holds typed values.
///
/// The same work on both: write a state, read it, call a command. Values are
/// a record of three fields, and a list of N of them where one item changes
/// per write (the usual way a list in an app changes). Then the cost of each
/// pass the registry makes over a value, alone.
///
/// Run: `fvm dart run benchmark/registry_bench.dart` (AOT:
/// `fvm dart compile exe benchmark/registry_bench.dart -o .tmp/bench && .tmp/bench`).
///
/// 2026-10-28, JIT, before typed values were kept as they are (every value
/// went through toJson, check, freeze and fromJson):
///
///     write one record           core   0.220 us  registry     1.980 us
///     write a list of 1000       core   2.145 us  registry  1168.921 us
///     write a list of 10000      core  17.430 us  registry 11961.560 us
///     read                       core   0.005 us  registry     0.070 us
///     a command call             core   0.104 us  registry    11.829 us
///
/// After typed values were kept as they are, and what is the same as the
/// value kept before passed unvisited:
///
///     write one record           core   0.220 us  registry     1.177 us
///     write a list of 1000       core   2.147 us  registry    17.142 us
///     write a list of 10000      core  17.735 us  registry    95.480 us
///     read                       core   0.005 us  registry     0.045 us
library;

import 'package:parlance/src/core/core.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/words.dart' show TypedRegistry;

typedef Item = ({String id, String title, bool done});

Map<String, Object?> _itemTo(Item v) => {
  'id': v.id,
  'title': v.title,
  'done': v.done,
};
Item _itemFrom(Map<String, Object?> m) => (
  id: m['id']! as String,
  title: m['title']! as String,
  done: m['done']! as bool,
);

const itemShape = RecordShape<Item>(
  {
    'id': Part(Plain(TextType())),
    'title': Part(Plain(TextType())),
    'done': Part(Plain(BoolType())),
  },
  to: _itemTo,
  from: _itemFrom,
  get: _itemAt,
);

Object? _itemAt(Item v, int i) => switch (i) {
  0 => v.id,
  1 => v.title,
  _ => v.done,
};

enum BenchState<T> implements IStateWord<T> {
  item<Item>('bench.item', itemShape),
  items<List<Item>>('bench.items', ListShape(itemShape));

  const BenchState(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

typedef Toggle = ({String id, bool done});
Map<String, Object?> _toggleTo(Toggle v) => {'id': v.id, 'done': v.done};
Toggle _toggleFrom(Map<String, Object?> m) =>
    (id: m['id']! as String, done: m['done']! as bool);

enum BenchCommand<P, R> implements ICommandWord<P, R> {
  toggle<Toggle, bool>(
    'bench.toggle',
    RecordShape(
      {'id': Part(Plain(TextType())), 'done': Part(Plain(BoolType()))},
      to: _toggleTo,
      from: _toggleFrom,
    ),
    returns: Plain(BoolType()),
  );

  const BenchCommand(this.name, this.params, {this.returns});
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

const host = Principal('host', 'bench');
const user = Principal('user', 'bench');

/// Microseconds per operation, the best of [rounds] after a warm-up.
double measure(int ops, void Function(int i) body, {int rounds = 5}) {
  for (var i = 0; i < ops ~/ 4 + 1; i++) {
    body(i);
  }
  var best = double.infinity;
  for (var r = 0; r < rounds; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < ops; i++) {
      body(i);
    }
    final us = sw.elapsedMicroseconds / ops;
    if (us < best) best = us;
  }
  return best;
}

Future<double> measureAsync(
  int ops,
  Future<void> Function(int i) body, {
  int rounds = 5,
}) async {
  for (var i = 0; i < ops ~/ 4 + 1; i++) {
    await body(i);
  }
  var best = double.infinity;
  for (var r = 0; r < rounds; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < ops; i++) {
      await body(i);
    }
    final us = sw.elapsedMicroseconds / ops;
    if (us < best) best = us;
  }
  return best;
}

void row(String name, double core, double registry) {
  final ratio = registry / core;
  print(
    '${name.padRight(34)} core ${_us(core)}  registry ${_us(registry)}'
    '  x${ratio.toStringAsFixed(1)}',
  );
}

String _us(double us) => '${us.toStringAsFixed(3).padLeft(10)} us';

List<Item> makeItems(int n) => [
  for (var i = 0; i < n; i++) (id: 'i$i', title: 'item number $i', done: false),
];

/// One item flipped: a new list, as an immutable app state changes.
List<Item> flip(List<Item> items, int i) {
  final at = i % items.length;
  final it = items[at];
  return [...items]..[at] = (id: it.id, title: it.title, done: !it.done);
}

int opsFor(int n) => n >= 10000 ? 200 : (n >= 100 ? 5000 : 200000);

Future<void> main() async {
  print('--- one record: write, read ---');
  {
    final state = LocalState<Item>();
    final w = state.claim();
    final r = Registry(onError: (e, _) => throw e);
    final s = r.state(BenchState.item).define(by: host);
    final reader = r.state(BenchState.item);
    final items = makeItems(2);
    row(
      'write',
      measure(200000, (i) => w.set(items[i & 1])),
      measure(200000, (i) => s.set(items[i & 1])),
    );
    Item? sink;
    row(
      'read',
      measure(200000, (_) => sink = state.value),
      measure(200000, (_) => sink = reader.read()),
    );
    if (sink == null) print('');
  }

  for (final n in [10, 100, 1000, 10000]) {
    print('--- a list of $n, one item changes per write ---');
    final state = LocalState<List<Item>>();
    final w = state.claim();
    final r = Registry(onError: (e, _) => throw e);
    final s = r.state(BenchState.items).define(by: host);
    final reader = r.state(BenchState.items);
    var a = makeItems(n);
    var b = makeItems(n);
    final ops = opsFor(n);
    row(
      'write',
      measure(ops, (i) => w.set(a = flip(a, i))),
      measure(ops, (i) => s.set(b = flip(b, i))),
    );
    List<Item>? sink;
    row(
      'read',
      measure(ops, (_) => sink = state.value),
      measure(ops, (_) => sink = reader.read()),
    );
    if (sink == null) print('');
  }

  print('--- a command call, answered at once ---');
  {
    final command = LocalCommand<Toggle, bool>()..serve((p) => p.done);
    final r = Registry(onError: (e, _) => throw e);
    r
        .command(BenchCommand.toggle)
        .define((c) => c.params.done, callers: Callers.only(['user']));
    final cmd = r.command(BenchCommand.toggle);
    row(
      'call',
      await measureAsync(50000, (i) => command.call((id: 'a', done: i.isEven))),
      await measureAsync(
        50000,
        (i) => cmd.call((id: 'a', done: i.isEven), by: user),
      ),
    );
  }

  print('--- the passes over a list, alone (us per write) ---');
  final r = Registry(onError: (e, _) => throw e);
  const shape = ListShape(itemShape);
  final type = shape.type;
  for (final n in [100, 1000, 10000]) {
    final items = makeItems(n);
    final json = shape.toJson(items);
    final checked = type.check(json, r);
    final frozen = freezeJson(checked);
    final other = freezeJson(shape.toJson(flip(items, 0)));
    final ops = opsFor(n);
    final to = measure(ops, (_) => shape.toJson(items));
    final check = measure(ops, (_) => type.check(json, r));
    final freeze = measure(ops, (_) => freezeJson(checked));
    final eq = measure(ops, (_) => jsonEquals(frozen, other));
    final from = measure(ops, (_) => shape.fromJson(frozen));
    print(
      'n=${'$n'.padRight(6)} toJson ${_us(to)}  check ${_us(check)}'
      '  freeze ${_us(freeze)}  equals ${_us(eq)}  fromJson ${_us(from)}',
    );
  }
}
