import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parlance/registry.dart';

import 'files.dart';

/// Writes a registry's journal (SPEC §9.3) as JSON lines, a file a day
/// (`journal-2026-10-28.jsonl`, by the UTC day of each entry), each entry
/// as it comes: written to the file before the next one comes, so what was
/// done before the app stopped is there, however it stopped. Files older
/// than [keep] go when it starts and when a day turns.
///
/// Without [payloads] it writes who did what, following what, and how it
/// ended, never the values: no params, payloads, values or answers.
///
/// Turned off ([on]), it stops listening: the registry then makes no entry
/// at all, and nothing is written or kept open.
final class JournalWriter {
  JournalWriter(
    this._journal, {
    required this.dir,
    this.keep = const Duration(days: 30),
    this.payloads = true,
    bool on = true,
    DateTime Function()? now,
    void Function(Object error, StackTrace stack)? onError,
  }) : _now = now ?? DateTime.now,
       _onError = onError ?? _ignore {
    this.on = on;
  }

  /// Where its files are.
  final Directory dir;

  /// How long a day's file is kept.
  final Duration keep;

  /// Whether values are written.
  final bool payloads;

  final Stream<JournalEntry> _journal;
  final DateTime Function() _now;
  final void Function(Object, StackTrace) _onError;
  StreamSubscription<JournalEntry>? _sub;
  RandomAccessFile? _file;
  String? _day;
  bool _closed = false;

  /// Whether it writes: on, it listens to the journal from now on; off, it
  /// does not, and closes its file.
  bool get on => _sub != null;
  set on(bool value) {
    if (value == on || (value && _closed)) return;
    if (value) {
      try {
        dir.createSync(recursive: true);
        _prune(_now());
      } catch (err, st) {
        _onError(err, st);
      }
      _sub = _journal.listen(_add);
    } else {
      unawaited(_sub!.cancel());
      _sub = null;
      _closeFile();
    }
  }

  void _closeFile() {
    try {
      _file?.closeSync();
    } catch (err, st) {
      _onError(err, st);
    }
    _file = null;
    _day = null;
  }

  static void _ignore(Object _, StackTrace _) {}

  void _add(JournalEntry e) {
    try {
      final day = dayOf(e.at);
      if (day != _day) {
        _file?.closeSync();
        _file = File(
          '${dir.path}/${fileOfDay(day)}',
        ).openSync(mode: FileMode.append);
        if (_day != null) _prune(e.at);
        _day = day;
      }
      final json = payloads ? e.toJson() : _bare(e.toJson());
      _file!.writeStringSync('${jsonEncode(json)}\n');
    } catch (err, st) {
      _onError(err, st);
    }
  }

  void _prune(DateTime now) {
    final oldest = dayOf(now.subtract(keep));
    for (final (day, f) in journalFiles(dir)) {
      if (day.compareTo(oldest) < 0) {
        try {
          f.deleteSync();
        } catch (err, st) {
          _onError(err, st);
        }
      }
    }
  }

  /// Stops writing for good; what was written stays.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    _sub = null;
    _closeFile();
  }
}

/// [json] without its values.
Map<String, Object?> _bare(Map<String, Object?> json) => {
  for (final MapEntry(:key, :value) in json.entries)
    if (!const {'params', 'payload', 'value', 'previous'}.contains(key))
      key: key == 'result' && value is Map
          ? {
              for (final r in value.entries)
                if (r.key != 'value') r.key as String: r.value,
            }
          : value,
};
