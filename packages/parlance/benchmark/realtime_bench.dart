/// A big typed document and frequent small changes, on the registry.
///
/// Run: `fvm dart compile exe benchmark/realtime_bench.dart -o .tmp/rt && .tmp/rt`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:parlance/registry.dart';

const host = Principal('host', 'bench');

typedef Check = ({
  String id,
  String text,
  bool passed,
  String? note,
  List<String> tags,
});
typedef Section = ({String title, List<Check> checks});
typedef Task = ({String id, int version, List<Section> sections});

const checkShape = RecordShape<Check>(
  {
    'id': Part(Plain(TextType())),
    'text': Part(Plain(TextType())),
    'passed': Part(Plain(BoolType())),
    'note': Part(Plain(TextType()), optional: true),
    'tags': Part(ListShape(Plain(TextType()))),
  },
  to: _checkTo,
  from: _checkFrom,
);
Map<String, Object?> _checkTo(Check c) => {
  'id': c.id,
  'text': c.text,
  'passed': c.passed,
  'note': c.note,
  'tags': c.tags,
};
Check _checkFrom(Map<String, Object?> m) => (
  id: m['id']! as String,
  text: m['text']! as String,
  passed: m['passed']! as bool,
  note: m['note'] as String?,
  tags: m['tags']! as List<String>,
);

const sectionShape = RecordShape<Section>(
  {'title': Part(Plain(TextType())), 'checks': Part(ListShape(checkShape))},
  to: _sectionTo,
  from: _sectionFrom,
);
Map<String, Object?> _sectionTo(Section s) => {
  'title': s.title,
  'checks': s.checks,
};
Section _sectionFrom(Map<String, Object?> m) =>
    (title: m['title']! as String, checks: m['checks']! as List<Check>);

const taskShape = RecordShape<Task>(
  {
    'id': Part(Plain(TextType())),
    'version': Part(Plain(IntType())),
    'sections': Part(ListShape(sectionShape)),
  },
  to: _taskTo,
  from: _taskFrom,
);
Map<String, Object?> _taskTo(Task t) => {
  'id': t.id,
  'version': t.version,
  'sections': t.sections,
};
Task _taskFrom(Map<String, Object?> m) => (
  id: m['id']! as String,
  version: m['version']! as int,
  sections: m['sections']! as List<Section>,
);

typedef Cursor = ({double x, double y});
const cursorShape = RecordShape<Cursor>(
  {'x': Part(Plain(NumType())), 'y': Part(Plain(NumType()))},
  to: _cursorTo,
  from: _cursorFrom,
);
Map<String, Object?> _cursorTo(Cursor c) => {'x': c.x, 'y': c.y};
Cursor _cursorFrom(Map<String, Object?> m) =>
    (x: (m['x']! as num).toDouble(), y: (m['y']! as num).toDouble());

enum RtState<T> implements IStateWord<T> {
  task<Task>('rt.task', taskShape),
  check<Check>('rt.check', checkShape, key: 'check'),
  cursor<Cursor>('rt.cursor', cursorShape, key: 'peer');

  const RtState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

Task makeTask(int sections, int version) => (
  id: 'task-1',
  version: version,
  sections: [
    for (var s = 0; s < sections; s++)
      (
        title: 'section $s',
        checks: [
          for (var c = 0; c < 20; c++)
            (
              id: 's$s-c$c',
              text: 'check $c of section $s, what to look at',
              passed: c.isEven,
              note: null,
              tags: const ['a', 'b'],
            ),
        ],
      ),
  ],
);

String ms(int us, int n) => '${(us / n / 1000).toStringAsFixed(2)} ms';
String us(int us, int n) => '${(us / n).toStringAsFixed(2)} us';

Future<void> main() async {
  breakdown();
  print('--- a typed document, rewritten whole ---');
  for (final sections in [100, 1000]) {
    final r = Registry(onError: (e, _) => throw e);
    final w = r.state(RtState.task).define(by: host);
    final s = r.state(RtState.task);
    final a = makeTask(sections, 1), b = makeTask(sections, 2);
    final kb = utf8.encode(jsonEncode(taskShape.toJson(a))).length ~/ 1024;
    w.set(a);
    const n = 10;
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      w.set(i.isEven ? b : a);
    }
    final write = sw.elapsedMicroseconds;
    sw
      ..reset()
      ..start();
    s.read();
    final first = sw.elapsedMicroseconds;
    sw
      ..reset()
      ..start();
    for (var i = 0; i < n; i++) {
      s.read();
    }
    final again = sw.elapsedMicroseconds;
    print(
      '$kb KB: write ${ms(write, n)}, first read ${ms(first, 1)}, '
      'read again ${us(again, n)}',
    );
  }

  print('--- frequent small changes ---');
  {
    // 10k checks as a keyed state; one toggled per write.
    final r = Registry(onError: (e, _) => throw e);
    final w = r.state(RtState.check).define(by: host);
    final checks = makeTask(500, 1).sections.expand((s) => s.checks).toList();
    r.batch(() {
      for (final c in checks) {
        w.set(c, key: c.id);
      }
    });
    const n = 100000;
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      final c = checks[i % checks.length];
      w.set((
        id: c.id,
        text: c.text,
        passed: i.isOdd,
        note: null,
        tags: c.tags,
      ), key: c.id);
    }
    print(
      'one check of ${checks.length}, keyed: ${us(sw.elapsedMicroseconds, n)} per write',
    );
  }

  for (final watchers in [0, 10, 100, 1000]) {
    // Peers' cursors: each widget watches one peer, every peer moves.
    final r = Registry(onError: (e, _) => throw e);
    final w = r.state(RtState.cursor).define(by: host);
    final s = r.state(RtState.cursor);
    const peers = 1000;
    var heard = 0;
    final subs = [
      for (var p = 0; p < watchers; p++)
        s.watch(key: 'p$p').listen((_) => heard++),
    ];
    await Future<void>.delayed(Duration.zero);
    heard = 0;
    const n = 50000;
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      w.set((x: i.toDouble(), y: 1), key: 'p${i % peers}');
    }
    final write = sw.elapsedMicroseconds;
    await Future<void>.delayed(Duration.zero);
    final total = sw.elapsedMicroseconds;
    print(
      'cursor writes, $watchers watchers: write ${us(write, n)}, '
      'with delivery ${us(total, n)} (heard $heard)',
    );
    for (final sub in subs) {
      await sub.cancel();
    }
  }
}

/// Where a whole-document write goes.
void breakdown() {
  final r = Registry(onError: (e, _) => throw e);
  final a = makeTask(1000, 1), b = makeTask(1000, 2);
  final type = taskShape.type;
  int t(void Function() f) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      f();
    }
    return sw.elapsedMicroseconds ~/ 5000;
  }

  final ja = taskShape.toJson(a);
  final ca = type.check(ja, r);
  final fa = freezeJson(ca);
  final fb = freezeJson(type.check(taskShape.toJson(b), r));
  print(
    'toJson ${t(() => taskShape.toJson(a))} ms, '
    'check ${t(() => type.check(ja, r))} ms, '
    'freeze ${t(() => freezeJson(ca))} ms, '
    'equals ${t(() => jsonEquals(fa, fb))} ms, '
    'fromJson ${t(() => taskShape.fromJson(fa))} ms',
  );
}
