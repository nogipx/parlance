import 'dart:convert';
import 'dart:io';

import 'package:parlance/registry.dart';

import 'files.dart';

/// Reads what a [JournalWriter] wrote in [dir], in the order it happened.
/// A line that is no entry (one cut short when the app stopped) is
/// skipped.
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
      for (final line in f.readAsLinesSync()) {
        if (line.isEmpty) continue;
        try {
          yield JournalEntry.fromJson(jsonDecode(line));
        } on Object {
          continue;
        }
      }
    }
  }

  /// Conversation [id] (SPEC §4), in order: every entry of it, and of
  /// what followed from one of them, however the registry named its
  /// conversation (a cause made by hand after the registry forgot its
  /// parent's starts one of its own, still following from it). [epoch]
  /// keeps it to one run, for an id a caller gave again in another.
  List<JournalEntry> conversation(
    String id, {
    String? epoch,
    DateTime? since,
    DateTime? until,
  }) {
    final ids = {id};
    final of = <JournalEntry>[];
    for (final e in entries(since: since, until: until)) {
      if (epoch != null && e.epoch != epoch) continue;
      if (ids.contains(e.conversation) || ids.contains(e.cause.parent)) {
        of.add(e);
        ids.add(e.id);
      }
    }
    return of;
  }

  /// The entries in trace [traceId] (a span's or a log line's), in order:
  /// from telemetry back to what was done.
  List<JournalEntry> trace(
    String traceId, {
    DateTime? since,
    DateTime? until,
  }) => [
    for (final e in entries(since: since, until: until))
      if (e.trace?.split('-') case [_, final t, _, _] when t == traceId) e,
  ];

  /// The links there are (SPEC §9.3): who called each command, and who said
  /// each fact, following what, how often, from the days given; a call
  /// refused counts apart. A call or a fact that followed from nothing
  /// follows from null; one whose parent is in no day read, from `?`.
  List<JournalLink> links({DateTime? since, DateTime? until}) {
    final names = <String, String>{};
    final done = <(String?, String, String), int>{};
    final refused = <(String?, String, String), int>{};
    for (final e in entries(since: since, until: until)) {
      final String name;
      final Map<(String?, String, String), int> counts;
      switch (e) {
        case JournalStart(:final call):
          (name, counts) = (call.command, done);
        case JournalEnd(:final call) when call.result is CallRefused:
          (name, counts) = (call.command, refused);
        case JournalFact(:final fact):
          (name, counts) = (fact.fact, done);
        case JournalEnd() || JournalWrite():
          continue;
      }
      names[e.id] = name;
      final parent = e.cause.parent;
      final k = (
        parent == null ? null : names[parent] ?? '?',
        e.cause.by.selector,
        name,
      );
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return [
      for (final k in {...done.keys, ...refused.keys})
        JournalLink(
          from: k.$1,
          by: k.$2,
          to: k.$3,
          count: done[k] ?? 0,
          refused: refused[k] ?? 0,
        ),
    ];
  }
}

/// [by] called command [to] (or said fact [to]) following [from], a
/// command or a fact: [count] times it ran or was said, [refused] times
/// the call was refused.
final class JournalLink {
  const JournalLink({
    required this.from,
    required this.by,
    required this.to,
    required this.count,
    this.refused = 0,
  });

  final String? from;
  final String by;
  final String to;
  final int count;
  final int refused;

  Map<String, Object?> toJson() => {
    'from': from,
    'by': by,
    'to': to,
    'count': count,
    if (refused > 0) 'refused': refused,
  };

  @override
  String toString() =>
      '${from ?? '-'} -> $by -> $to x$count'
      '${refused > 0 ? ' (refused x$refused)' : ''}';
}
