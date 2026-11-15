import 'dart:convert';
import 'dart:developer' as developer;

import 'package:parlance/tools.dart';

import 'tree.dart';

/// A bounded description of incomplete or unreadable recording data.
final class JournalIssue {
  /// One issue without retaining the original (possibly large) input line.
  const JournalIssue(this.line, this.reason);

  /// The one-based source line; zero for an unreadable file.
  final int line;

  /// A short explanation of the missing evidence.
  final String reason;
}

/// What is told of a line that is an entry of a kind this build does not
/// know (a journal of a newer parlance): [kind] is the kind the line
/// names; [line] is the line itself. The line is skipped either way; this
/// says why.
typedef UnknownJournalLine = void Function(String kind, String line);

/// What unknown kinds are told to with no [UnknownJournalLine] given: the
/// first line of each kind, in the developer log (warning,
/// `parlance.journal`), so reading a newer journal is not silent; once per
/// kind, so a newer journal cannot flood it.
UnknownJournalLine tellUnknownKindsOnce() {
  final told = <String>{};
  return (kind, line) {
    if (told.length >= 64) return;
    kind = kind.length > 128 ? kind.substring(0, 128) : kind;
    if (told.add(kind)) {
      developer.log(
        'a journal entry of kind "$kind" was skipped: '
        'this build does not know it',
        name: 'parlance.journal',
        level: 900,
      );
    }
  };
}

/// The entries of JSON lines, as a [JournalWriter] writes them: one a
/// line, in order. A line that is no entry (one cut short when the app
/// stopped) is skipped; a line of a kind this build does not know (a
/// journal of a newer parlance) is skipped too, and told to [onUnknown],
/// or, without it, once per kind in the developer log.
Iterable<JournalEntry> parseJournal(
  String lines, {
  UnknownJournalLine? onUnknown,
  void Function(JournalIssue issue)? onIssue,
}) => JournalParser(onUnknown: onUnknown, onIssue: onIssue).parse(lines);

/// Reads successive file chunks with sequence continuity at file boundaries.
/// Retains sequence numbers for at most 32 epochs, without a payload cache.
final class JournalParser {
  /// One scan, with the same reporting hooks as [parseJournal].
  JournalParser({UnknownJournalLine? onUnknown, this.onIssue})
    : _tell = onUnknown ?? tellUnknownKindsOnce();

  final UnknownJournalLine _tell;

  /// Receives bounded issue descriptions; no source lines are retained.
  final void Function(JournalIssue issue)? onIssue;
  final Map<String, int> _positions = {};

  /// The next file's entries, preserving sequence checks across earlier files.
  Iterable<JournalEntry> parse(String lines) sync* {
    var number = 0;
    for (final line in const LineSplitter().convert(lines)) {
      number++;
      if (line.trim().isEmpty) continue;
      try {
        final entry = JournalEntry.fromJson(jsonDecode(line));
        final previous = _positions[entry.epoch];
        if (entry.n > 0) {
          if (previous != null && entry.n != previous + 1) {
            onIssue?.call(
              JournalIssue(number, 'journal sequence $previous -> ${entry.n}'),
            );
          }
          _positions[entry.epoch] = entry.n;
          if (_positions.length > 32) _positions.remove(_positions.keys.first);
        }
        yield entry;
      } on Object catch (e) {
        final reason = switch (e) {
          FormatException() => 'malformed or unsupported journal entry',
          TypeError() => 'invalid journal entry shape',
          _ => 'unreadable journal entry (${e.runtimeType})',
        };
        onIssue?.call(
          JournalIssue(
            number,
            reason.length > 256 ? reason.substring(0, 256) : reason,
          ),
        );
        if (e case FormatException(
          :final message,
        ) when message.startsWith('no journal entry of kind ')) {
          _tell(message.substring('no journal entry of kind '.length), line);
        }
        // What is no entry at all (a cut-short line) or no entry for this
        // build goes by; the difference is only whether it is told.
      }
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
  factory Journal.parse(
    String lines, {
    UnknownJournalLine? onUnknown,
    void Function(JournalIssue issue)? onIssue,
  }) => Journal(
    parseJournal(lines, onUnknown: onUnknown, onIssue: onIssue).toList(),
  );

  final Iterable<JournalEntry> entries;

  /// Conversation [id] (SPEC §4), in order: every entry of it, and of
  /// what followed from one of them, however the registry named its
  /// conversation (a cause made by hand after the registry forgot its
  /// parent's starts one of its own, still following from it). [epoch]
  /// keeps it to one run, for an id a caller gave again in another.
  List<JournalEntry> conversation(String id, {String? epoch}) {
    final ids = <String, Set<String>>{};
    final selectedEpochs = <String>{};
    final of = <JournalEntry>[];
    for (final e in entries) {
      if (epoch != null && e.epoch != epoch) continue;
      final within = ids.putIfAbsent(e.epoch, () => {id});
      if (within.contains(e.conversation) || within.contains(e.cause.parent)) {
        of.add(e);
        within.add(e.id);
        selectedEpochs.add(e.epoch);
      }
    }
    if (epoch == null && selectedEpochs.length > 1) {
      throw ArgumentError(
        'conversation $id occurs in several epochs; specify epoch',
      );
    }
    return of;
  }

  /// The conversation message [id] (a call's, a fact's, a write's, at any
  /// depth) is part of, whole and in order: what a line of a log naming
  /// one message was in. Empty when it is not here.
  String? _epochFor(String id, String? epoch) {
    if (epoch != null) return epoch;
    final runs = {
      for (final e in entries)
        if (e.id == id) e.epoch,
    };
    if (runs.length > 1) {
      throw ArgumentError(
        'message $id occurs in several epochs; specify epoch',
      );
    }
    return runs.firstOrNull;
  }

  List<JournalEntry> of(String id, {String? epoch}) {
    epoch = _epochFor(id, epoch);
    for (final e in entries) {
      if (e.id == id && e.epoch == epoch) {
        return conversation(e.conversation, epoch: e.epoch);
      }
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
  List<JournalEntry> pathTo(String id, {String? epoch}) {
    epoch = _epochFor(id, epoch);
    final byId = <(String, String), JournalEntry>{};
    final starts = <String>{};
    final ambiguous = <String>{};
    for (final e in entries) {
      if (e.epoch != epoch) continue;
      if ((e is JournalStart && (e.call.ambiguous || !starts.add(e.id))) ||
          (e is JournalEnd && e.call.ambiguous)) {
        ambiguous.add(e.id);
      }
      byId.putIfAbsent((e.epoch, e.id), () => e);
    }
    if (epoch == null) return const [];
    final path = <JournalEntry>[];
    final seen = <String>{};
    for (String? at = id; at != null && seen.add(at);) {
      if (ambiguous.contains(at)) {
        throw ArgumentError('multiple executions of $at in epoch $epoch');
      }
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

  /// Committed writes of one state/key across conversations, in recorded order.
  List<JournalWrite> history(
    String state, {
    String? key,
    String? epoch,
    int count = 100,
  }) {
    final result = <JournalWrite>[];
    final max = count.clamp(0, 1000);
    if (max == 0) return result;
    for (final entry in entries) {
      if (entry is JournalWrite &&
          entry.word == state &&
          entry.change.key == key &&
          (epoch == null || entry.epoch == epoch)) {
        result.add(entry);
        if (result.length > max) result.removeAt(0);
      }
    }
    return result;
  }

  /// The entries in trace [traceId] (a span's or a log line's), in order:
  /// from telemetry back to what was done.
  List<JournalEntry> trace(String traceId) => [
    for (final e in entries)
      if (e.trace?.split('-') case [_, final t, _, _] when t == traceId) e,
  ];

  /// Each conversation here, in the order it started: what it started
  /// with, when, how long it went on and how its calls ended.
  List<JournalConversation> conversations({bool includeDiagnostics = false}) {
    final all = <(String, String), JournalConversation>{};
    for (final e in entries) {
      if (e is JournalDiagnostic && e.event.startsWith('capture.')) continue;
      final c = all[(e.epoch, e.conversation)] ??= JournalConversation._(
        e.conversation,
        e.epoch,
        e.origin,
        e.at,
      );
      c._add(e);
    }
    return all.values
        .where((c) => includeDiagnostics || !c.metadataOnly)
        .toList();
  }

  /// The links there are (SPEC §9.3): who called each command, and who said
  /// each fact, following what, how often; a call refused counts apart. A
  /// call or a fact that followed from nothing follows from null; one
  /// whose parent is not here, from `?`.
  List<JournalLink> links() {
    final names = <(String, String), String>{};
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
        case JournalEnd() || JournalWrite() || JournalDiagnostic():
          continue;
      }
      names[(e.epoch, e.id)] = name;
      final parent = e.cause.parent;
      final k = (
        parent == null ? null : names[(e.epoch, parent)] ?? '?',
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

  /// True for standalone catalog/coverage metadata without an interaction.
  bool get metadataOnly => _metadataOnly;
  bool _metadataOnly = true;

  /// How many of its calls began, and how many ended so.
  int get calls => _calls;
  int _calls = 0;
  int get refused => _refused;
  int _refused = 0;
  int get failed => _failed;
  int _failed = 0;
  int get timedOut => _timedOut;
  int _timedOut = 0;

  /// How many of its calls were cancelled by their caller and how many
  /// went lost on the way: not failures, and not ends to read as peaceful.
  int get cancelled => _cancelled;
  int _cancelled = 0;
  int get lost => _lost;
  int _lost = 0;

  Duration get duration => _last.difference(started);

  bool _lateCallerStopped = false;

  /// A known failure or interrupted caller, including a late record captured alone.
  bool get hasProblems =>
      refused + failed + timedOut + cancelled + lost > 0 || _lateCallerStopped;

  void _add(JournalEntry e) {
    if (e case JournalEnd(
      call: CallRecord(
        late: true,
        replyResult: CallTimedOut() || CallCancelled(),
      ),
    )) {
      _lateCallerStopped = true;
    }
    _entries++;
    if (e is! JournalDiagnostic ||
        e.event.startsWith('stream.') ||
        e.data.containsKey('operation')) {
      _metadataOnly = false;
    }
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
          case CallCancelled():
            _cancelled++;
          case CallLost():
            _lost++;
          case CallDone():
            break;
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
