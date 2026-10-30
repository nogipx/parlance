import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:parlance/tools.dart';

import 'files.dart';

/// Writes a registry's journal (SPEC §9.3) as JSON lines, a file a day
/// (`journal-2026-10-28.jsonl`, by the UTC day of each entry), each entry
/// as it comes: written to the file before the next one comes, so what was
/// done before the app stopped is there, however it stopped. What was
/// written is made durable (an fsync) at most [fsyncEvery] behind the last
/// entry and when the day turns or it closes: a crash of the app loses
/// nothing written, a crash of the machine loses at most what is not yet
/// fsynced. Files older than [keep] go when it starts and when a day turns.
///
/// Without [payloads] it writes who did what, following what, and how it
/// ended, never the values: no params, payloads, values or answers.
///
/// Turned off ([on]), it stops listening: the registry then makes no entry
/// at all, and nothing is written or kept open.
///
/// A write error goes to [onError]; without it, it is reported to
/// `dart:developer` (level warning, name `parlance.journal`), so a journal
/// that cannot write is not silent: it is heard in DevTools and `dart run`.
final class JournalWriter {
  JournalWriter(
    this._journal, {
    required this.dir,
    this.keep = const Duration(days: 30),
    this.payloads = true,
    this.fsyncEvery = const Duration(milliseconds: 200),
    bool on = true,
    DateTime Function()? now,
    void Function(Object error, StackTrace stack)? onError,
  }) : _now = now ?? DateTime.now,
       _onError = onError ?? _report {
    this.on = on;
  }

  /// Where its files are.
  final Directory dir;

  /// How long a day's file is kept.
  final Duration keep;

  /// Whether values are written.
  final bool payloads;

  /// How far behind the last written entry making it durable may lag:
  /// an fsync at most this often, and always when the day turns or it
  /// closes.
  final Duration fsyncEvery;

  final Stream<JournalEntry> _journal;
  final DateTime Function() _now;
  final void Function(Object, StackTrace) _onError;
  StreamSubscription<JournalEntry>? _sub;
  RandomAccessFile? _file;
  File? _path;
  String? _day;
  DateTime? _fsynced;
  bool _closed = false;

  /// Whether it writes: on, it listens to the journal from now on; off, it
  /// does not, and closes its file.
  bool get on => _sub != null;
  set on(bool value) {
    if (value == on || (value && _closed)) return;
    if (value) {
      _prune(_now());
      _sub = _journal.listen(_add);
    } else {
      unawaited(_sub!.cancel());
      _sub = null;
      _closeFile();
    }
  }

  void _closeFile() {
    final file = _file;
    if (file != null) {
      try {
        file.flushSync();
      } catch (err, st) {
        _onError(err, st);
      }
      try {
        file.closeSync();
      } catch (err, st) {
        _onError(err, st);
      }
    }
    _file = null;
    _day = null;
    _fsynced = null;
  }

  static void _report(Object error, StackTrace stack) {
    developer.log(
      'a journal entry was not written: $error',
      name: 'parlance.journal',
      level: 900,
      error: error,
      stackTrace: stack,
    );
  }

  void _add(JournalEntry e) {
    final day = dayOf(e.at);
    var turned = false;
    try {
      // A file gone while it was open (its folder removed) is opened
      // again: else what is written goes nowhere until the day turns.
      if (day != _day || !_path!.existsSync()) {
        turned = _day != null && day != _day;
        // Closed and forgotten first: a file that would not open is
        // opened again with the next entry, not the closed one kept.
        _closeFile();
        _file = _open(_path = File('${dir.path}/${fileOfDay(day)}'));
        _day = day;
        _fsynced = null;
      }
      final json = payloads ? e.toJson() : _bare(e.toJson());
      _file!.writeStringSync('${jsonEncode(json)}\n');
      // Made durable at most fsyncEvery behind the last entry: an fsync
      // on every entry would make a burst of them (a fader dragged) wait
      // on the disk each time.
      if (_fsynced == null || e.at.difference(_fsynced!) >= fsyncEvery) {
        _file!.flushSync();
        _fsynced = e.at;
      }
    } catch (err, st) {
      _onError(err, st);
    }
    if (turned) _prune(e.at);
  }

  /// [f] to append to, its last line ended if it was cut short (the app
  /// stopped while writing it): the next entry is a line of its own.
  RandomAccessFile _open(File f) {
    dir.createSync(recursive: true);
    final file = f.openSync(mode: FileMode.append);
    try {
      final length = file.lengthSync();
      if (length > 0) {
        file.setPositionSync(length - 1);
        if (file.readByteSync() != 0x0A) file.writeByteSync(0x0A);
      }
    } catch (_) {
      file.closeSync();
      rethrow;
    }
    return file;
  }

  void _prune(DateTime now) {
    final oldest = dayOf(now.subtract(keep));
    try {
      for (final (day, f) in journalFiles(dir)) {
        if (day.compareTo(oldest) < 0) {
          try {
            f.deleteSync();
          } catch (err, st) {
            _onError(err, st);
          }
        }
      }
    } catch (err, st) {
      _onError(err, st);
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
