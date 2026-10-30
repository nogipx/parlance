/// A big typed document and frequent small changes, on the registry. Its
/// record shapes read fields by place (`get`), as the generator makes them.
///
/// Run: `fvm dart compile exe benchmark/realtime_bench.dart -o .tmp/rt && .tmp/rt`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

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
    'id': Part(PlainShape(TextType())),
    'text': Part(PlainShape(TextType())),
    'passed': Part(PlainShape(BoolType())),
    'note': Part(PlainShape(TextType()), optional: true),
    'tags': Part(ListShape(PlainShape(TextType()))),
  },
  to: _checkTo,
  from: _checkFrom,
  get: _checkAt,
);
Object? _checkAt(Check c, int i) => switch (i) {
  0 => c.id,
  1 => c.text,
  2 => c.passed,
  3 => c.note,
  _ => c.tags,
};
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
  {
    'title': Part(PlainShape(TextType())),
    'checks': Part(ListShape(checkShape)),
  },
  to: _sectionTo,
  from: _sectionFrom,
  get: _sectionAt,
);
Object? _sectionAt(Section s, int i) => i == 0 ? s.title : s.checks;
Map<String, Object?> _sectionTo(Section s) => {
  'title': s.title,
  'checks': s.checks,
};
Section _sectionFrom(Map<String, Object?> m) =>
    (title: m['title']! as String, checks: m['checks']! as List<Check>);

const taskShape = RecordShape<Task>(
  {
    'id': Part(PlainShape(TextType())),
    'version': Part(PlainShape(IntType())),
    'sections': Part(ListShape(sectionShape)),
  },
  to: _taskTo,
  from: _taskFrom,
  get: _taskAt,
);
Object? _taskAt(Task t, int i) => switch (i) {
  0 => t.id,
  1 => t.version,
  _ => t.sections,
};
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
  {'x': Part(PlainShape(NumType())), 'y': Part(PlainShape(NumType()))},
  to: _cursorTo,
  from: _cursorFrom,
  get: _cursorAt,
);
Object? _cursorAt(Cursor c, int i) => i == 0 ? c.x : c.y;
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
    final words = GeneratedWords(
      r.participant(host, vocabularies: [WordSet.open('rt')]),
    );
    final w = words.state(RtState.task).define();
    final s = words.stateOf(RtState.task);
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
    s.value;
    final first = sw.elapsedMicroseconds;
    sw
      ..reset()
      ..start();
    for (var i = 0; i < n; i++) {
      s.value;
    }
    final again = sw.elapsedMicroseconds;
    print(
      '$kb KB: write ${ms(write, n)}, first read ${ms(first, 1)}, '
      'read again ${us(again, n)}',
    );
  }

  print('--- frequent small changes ---');
  {
    // 10k checks as a keyed state; one toggled per write: each write is a
    // change, of what that check holds now.
    final r = Registry(onError: (e, _) => throw e);
    final words = GeneratedWords(
      r.participant(host, vocabularies: [WordSet.open('rt')]),
    );
    final w = words.state(RtState.check).define();
    final checks = makeTask(500, 1).sections.expand((s) => s.checks).toList();
    final passed = [for (final c in checks) c.passed];
    r.batch(() {
      for (final c in checks) {
        w.set(c, key: c.id);
      }
    });
    Check toggled(int i) {
      final c = checks[i];
      return (
        id: c.id,
        text: c.text,
        passed: passed[i] = !passed[i],
        note: null,
        tags: c.tags,
      );
    }

    const n = 100000;
    for (var i = 0; i < n ~/ 10; i++) {
      w.set(toggled(i % checks.length), key: checks[i % checks.length].id);
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      final at = i % checks.length;
      w.set(toggled(at), key: checks[at].id);
    }
    final changed = sw.elapsedMicroseconds;
    // The same again: what a write that changes nothing costs.
    sw
      ..reset()
      ..start();
    for (var i = 0; i < n; i++) {
      final at = i % checks.length;
      final c = checks[at];
      w.set((
        id: c.id,
        text: c.text,
        passed: passed[at],
        note: null,
        tags: c.tags,
      ), key: c.id);
    }
    print(
      'one check of ${checks.length}, keyed: ${us(changed, n)} per write '
      'that changes it, ${us(sw.elapsedMicroseconds, n)} per write of what '
      'it holds',
    );
  }

  for (final watchers in [0, 10, 100, 1000]) {
    // Peers' cursors: each widget watches one peer, every peer moves.
    final r = Registry(onError: (e, _) => throw e);
    final words = GeneratedWords(
      r.participant(host, vocabularies: [WordSet.open('rt')]),
    );
    final w = words.state(RtState.cursor).define();
    final s = words.keyedOf(RtState.cursor);
    const peers = 1000;
    var heard = 0;
    final subs = [
      for (var p = 0; p < watchers; p++)
        s.changesOf('p$p').listen((_) => heard++),
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
