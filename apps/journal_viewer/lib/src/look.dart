import 'package:flutter/material.dart';
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
  static const write = Color(0xFF8B949E);

  static const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

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
