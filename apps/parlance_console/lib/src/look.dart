import 'package:material_ui/material_ui.dart';
import 'package:parlance_journal/journal.dart';

import 'viewer.dart';

/// The colours of how things went, the same in every view.
abstract final class Look {
  static const done = Color(0xFF3FB68B);
  static const refused = Color(0xFFE8913A);
  static const failed = Color(0xFFE5534B);
  static const slow = Color(0xFFD4B13C);
  static const running = Color(0xFF4C9AFF);
  static const fact = Color(0xFFB083F0);
  static const write = Color(0xFF6BD7CF);

  static const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

  static final _header = RegExp(
    r'^(\d\d:\d\d:\d\d(?:\.\d+)? )\[(.*?)\] (INTERNAL|TRACE|DEBUG|INFO|WARNING|ERROR|FATAL|SPAN)(\s+)(\S+)(  .*)$',
  );
  static final _spanOutcome = RegExp(r' \d+ms (\w+)');

  static ({String? device, TextSpan text}) logLine(String line) {
    final m = _header.firstMatch(line);
    if (m == null) return (device: null, text: TextSpan(text: line));
    final status = _spanOutcome.firstMatch(m[6]!)?.group(1);
    final color = switch (m[3]) {
      'ERROR' || 'FATAL' => failed,
      'WARNING' => refused,
      'INFO' => running,
      'SPAN' => switch (status) {
        'ok' => done,
        'error' || 'failed' => failed,
        'cancelled' => slow,
        _ => fact,
      },
      _ => const Color(0xFFA6AFBE),
    };
    return (
      device: m[2],
      text: TextSpan(
        children: [
          TextSpan(
            text: '${m[1]}[${m[2]}] ',
            style: const TextStyle(color: Color(0xFFA6AFBE)),
          ),
          TextSpan(
            text: m[3],
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: '${m[4]}${m[5]}',
            style: const TextStyle(color: write),
          ),
          TextSpan(text: m[6]),
        ],
      ),
    );
  }

  static Color of(JournalNode n) => switch (n.kind) {
    'fact' => fact,
    'write' => write,
    _ => switch (outcomeOf(n)) {
      null => running,
      'done' => done,
      'refused' => refused,
      'failed' || 'lost' => failed,
      _ => slow,
    },
  };

  static IconData iconOf(JournalNode n) => switch (n.kind) {
    'fact' => Icons.bolt,
    'write' => Icons.edit_outlined,
    'stream' => Icons.swap_vert,
    'diagnostic' => Icons.info_outline,
    _ => Icons.call_made,
  };
}

/// [at] in local time to the millisecond: `14:03:21.507`.
String clockOf(DateTime at) {
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '.${t.millisecond.toString().padLeft(3, '0')}';
}

/// [at] in local time with its day: `2026-10-28 14:03:21`.
String dayClockOf(DateTime at) {
  final t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// [d] as short as it reads: `840 ms`, `2.4 s`, `3 min 5 s`, `2 h 4 min`.
String spanOf(Duration d) {
  final ms = d.inMilliseconds;
  if (ms < 1000) return '$ms ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)} s';
  if (d.inHours < 1) return '${d.inMinutes} min ${d.inSeconds % 60} s';
  return '${d.inHours} h ${d.inMinutes % 60} min';
}

/// A bounded history label; collections open in details without serializing every
/// retained value while building the collapsed history list.
String previewOf(Object? value) => switch (value) {
  String() => value.length <= 96 ? value : '${value.substring(0, 96)}…',
  List<Object?>() =>
    '[${value.length} ${value.length == 1 ? 'item' : 'items'}]',
  Map<Object?, Object?>() =>
    '{${value.length} ${value.length == 1 ? 'field' : 'fields'}}',
  null => 'null',
  num() || bool() => '$value',
  _ => '<value>',
};
