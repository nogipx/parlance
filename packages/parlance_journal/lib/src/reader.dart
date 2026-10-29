import 'dart:convert';
import 'dart:io';

import 'package:parlance/registry.dart';

import 'files.dart';
import 'journal.dart';
import 'tree.dart';

/// Reads what a [JournalWriter] wrote in [dir], in the order it happened,
/// the days asked for only: each question is a [Journal]'s, over the
/// files, read again for each one. A line that is no entry (one cut short
/// when the app stopped) is skipped, and a day it cannot read.
final class JournalReader {
  JournalReader(this.dir);

  final Directory dir;

  /// Its files, the oldest day first.
  List<File> get files => [for (final (_, f) in journalFiles(dir)) f];

  /// Every entry of the days from [since] to [until] (UTC days, both
  /// included; all when null), in order.
  Iterable<JournalEntry> entries({DateTime? since, DateTime? until}) sync* {
    final from = since == null ? null : dayOf(since);
    final to = until == null ? null : dayOf(until);
    for (final (day, f) in journalFiles(dir)) {
      if (from != null && day.compareTo(from) < 0) continue;
      if (to != null && day.compareTo(to) > 0) continue;
      final List<int> bytes;
      try {
        bytes = f.readAsBytesSync();
      } on FileSystemException {
        // A day it may not read now (gone since listed, locked) is passed
        // over, as a line that is no entry is: the other days are read.
        continue;
      }
      for (final line in _lines(bytes)) {
        if (line.isEmpty) continue;
        try {
          yield JournalEntry.fromJson(jsonDecode(line));
        } on Object {
          continue;
        }
      }
    }
  }

  /// Writes the days from [since] to [until] (UTC days, both included;
  /// all when null) to [to] as one file of JSON lines, oldest first, the
  /// lines as they were written: what to send or open elsewhere (a
  /// viewer reads it as it reads the days). Answers how many lines it
  /// wrote; none and no file when there are none.
  Future<int> export(File to, {DateTime? since, DateTime? until}) async {
    final from = since == null ? null : dayOf(since);
    final last = until == null ? null : dayOf(until);
    final days = [
      for (final (day, f) in journalFiles(dir))
        if ((from == null || day.compareTo(from) >= 0) &&
            (last == null || day.compareTo(last) <= 0))
          f,
    ];
    var lines = 0;
    IOSink? out;
    try {
      for (final f in days) {
        final List<int> bytes;
        try {
          bytes = await f.readAsBytes();
        } on FileSystemException {
          continue;
        }
        for (final line in _lines(bytes)) {
          if (line.trim().isEmpty) continue;
          (out ??= to.openWrite()).writeln(line);
          lines++;
        }
      }
    } finally {
      await out?.close();
    }
    return lines;
  }

  /// The days from [since] to [until], as a [Journal] to ask.
  Journal days({DateTime? since, DateTime? until}) =>
      Journal(entries(since: since, until: until));

  /// [Journal.conversation], of the days given.
  List<JournalEntry> conversation(
    String id, {
    String? epoch,
    DateTime? since,
    DateTime? until,
  }) => days(since: since, until: until).conversation(id, epoch: epoch);

  /// [Journal.of], of the days given.
  List<JournalEntry> of(String id, {DateTime? since, DateTime? until}) =>
      days(since: since, until: until).of(id);

  /// [Journal.tree], of the days given.
  List<JournalNode> tree(
    String id, {
    String? epoch,
    DateTime? since,
    DateTime? until,
  }) => days(since: since, until: until).tree(id, epoch: epoch);

  /// [Journal.pathTo], of the days given.
  List<JournalEntry> pathTo(String id, {DateTime? since, DateTime? until}) =>
      days(since: since, until: until).pathTo(id);

  /// [Journal.startedWith], of the days given.
  List<JournalEntry> startedWith(
    String word, {
    Principal? by,
    DateTime? since,
    DateTime? until,
  }) => days(since: since, until: until).startedWith(word, by: by);

  /// [Journal.trace], of the days given.
  List<JournalEntry> trace(
    String traceId, {
    DateTime? since,
    DateTime? until,
  }) => days(since: since, until: until).trace(traceId);

  /// [Journal.links], of the days given.
  List<JournalLink> links({DateTime? since, DateTime? until}) =>
      days(since: since, until: until).links();
}

/// The lines of a file, a character cut short when the app stopped (its
/// last line) read as one not known rather than the day not read at all.
List<String> _lines(List<int> bytes) =>
    const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true));
