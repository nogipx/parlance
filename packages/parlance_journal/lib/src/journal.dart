import 'dart:convert';

import 'package:parlance/registry.dart';

import 'tree.dart';

/// The entries of JSON lines, as a [JournalWriter] writes them: one a
/// line, in order. A line that is no entry (one cut short when the app
/// stopped) is skipped.
Iterable<JournalEntry> parseJournal(String lines) sync* {
  for (final line in const LineSplitter().convert(lines)) {
    if (line.trim().isEmpty) continue;
    try {
      yield JournalEntry.fromJson(jsonDecode(line));
    } on Object {
      continue;
    }
  }
}

/// A journal's entries, in the order they happened, and what can be asked
/// of them: a conversation, the one a message is in, how a message came
/// about, a conversation as a tree, all that one word started, a trace,
/// the links there are. It reads nothing itself, so it serves a file read
/// on a Mac and one dropped in a browser alike.
///
/// [entries] is walked again for each question: a list, or anything that
/// can be walked twice (a reader's days).
final class Journal {
  const Journal(this.entries);

  /// The entries of JSON lines ([parseJournal]).
  factory Journal.parse(String lines) => Journal(parseJournal(lines).toList());

  final Iterable<JournalEntry> entries;

  /// Conversation [id] (SPEC §4), in order: every entry of it, and of
  /// what followed from one of them, however the registry named its
  /// conversation (a cause made by hand after the registry forgot its
  /// parent's starts one of its own, still following from it). [epoch]
  /// keeps it to one run, for an id a caller gave again in another.
  List<JournalEntry> conversation(String id, {String? epoch}) {
    final ids = {id};
    final of = <JournalEntry>[];
    for (final e in entries) {
      if (epoch != null && e.epoch != epoch) continue;
      if (ids.contains(e.conversation) || ids.contains(e.cause.parent)) {
        of.add(e);
        ids.add(e.id);
      }
    }
    return of;
  }

  /// The conversation message [id] (a call's, a fact's, a write's, at any
  /// depth) is part of, whole and in order: what a line of a log naming
  /// one message was in. Empty when it is not here.
  List<JournalEntry> of(String id) {
    for (final e in entries) {
      if (e.id == id) return conversation(e.conversation, epoch: e.epoch);
    }
    return const [];
  }

  /// Conversation [id] as a tree, to draw: its first message, what each
  /// message led to under it; a call with how it ended.
  List<JournalNode> tree(String id, {String? epoch}) =>
      treeOf(conversation(id, epoch: epoch));

  /// How message [id] came about: the messages it follows from, each the
  /// parent of the next, from the first of its conversation to it; a call
  /// as it began (as it ended, when it was refused). It starts later when
  /// a parent is not here.
  List<JournalEntry> pathTo(String id) {
    final byId = <(String, String), JournalEntry>{};
    String? epoch;
    for (final e in entries) {
      byId.putIfAbsent((e.epoch, e.id), () => e);
      if (e.id == id) epoch = e.epoch;
    }
    if (epoch == null) return const [];
    final path = <JournalEntry>[];
    final seen = <String>{};
    for (String? at = id; at != null && seen.add(at);) {
      final e = byId[(epoch, at)];
      if (e == null) break;
      path.add(e);
      at = e.cause.parent;
    }
    return path.reversed.toList();
  }

  /// Every entry of the conversations that started with [word] (a
  /// command called, a fact said), of [by] when given, in order: all that
  /// a message, a press, a ring led to.
  List<JournalEntry> startedWith(String word, {Principal? by}) => [
    for (final e in entries)
      if (e.origin case Origin(
        word: final w,
        by: final b,
      ) when w == word && (by == null || b == by))
        e,
  ];

  /// The entries in trace [traceId] (a span's or a log line's), in order:
  /// from telemetry back to what was done.
  List<JournalEntry> trace(String traceId) => [
    for (final e in entries)
      if (e.trace?.split('-') case [_, final t, _, _] when t == traceId) e,
  ];

  /// Each conversation here, in the order it started: what it started
  /// with, when, how long it went on and how its calls ended.
  List<JournalConversation> conversations() {
    final all = <(String, String), JournalConversation>{};
    for (final e in entries) {
      final c = all[(e.epoch, e.conversation)] ??= JournalConversation._(
        e.conversation,
        e.epoch,
        e.origin,
        e.at,
      );
      c._add(e);
    }
    return all.values.toList();
  }

  /// The links there are (SPEC §9.3): who called each command, and who said
  /// each fact, following what, how often; a call refused counts apart. A
  /// call or a fact that followed from nothing follows from null; one
  /// whose parent is not here, from `?`.
  List<JournalLink> links() {
    final names = <String, String>{};
    final done = <(String?, String, String), int>{};
    final refused = <(String?, String, String), int>{};
    for (final e in entries) {
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

/// One conversation, in brief: what it started with and when, how long it
/// went on, how many messages it had and how its calls ended.
final class JournalConversation {
  JournalConversation._(this.id, this.epoch, this.origin, this.started)
    : _last = started;

  /// Its id: its first message's.
  final String id;

  /// The registry's run it is of.
  final String epoch;

  /// What it started with: the first message's word and who.
  final Origin origin;

  /// When its first entry was.
  final DateTime started;

  /// When its last entry was.
  DateTime get last => _last;
  DateTime _last;

  /// How many entries it has.
  int get entries => _entries;
  int _entries = 0;

  /// How many of its calls began, and how many ended so.
  int get calls => _calls;
  int _calls = 0;
  int get refused => _refused;
  int _refused = 0;
  int get failed => _failed;
  int _failed = 0;
  int get timedOut => _timedOut;
  int _timedOut = 0;

  Duration get duration => _last.difference(started);

  void _add(JournalEntry e) {
    _entries++;
    if (e.at.isAfter(_last)) _last = e.at;
    switch (e) {
      case JournalStart():
        _calls++;
      case JournalEnd(:final call) when !call.late:
        switch (call.result) {
          case CallRefused():
            _calls++;
            _refused++;
          case CallFailed():
            _failed++;
          case CallTimedOut():
            _timedOut++;
          case _:
        }
      case _:
    }
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
