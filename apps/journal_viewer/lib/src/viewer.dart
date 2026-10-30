import 'package:flutter/foundation.dart';
import 'package:parlance/tools.dart';
import 'package:parlance_journal/journal.dart';

/// A journal file as loaded: its name and its lines.
typedef JournalFile = ({String name, String text});

/// What the viewer shows: the journal loaded, the conversations in it as
/// filtered, the one chosen and the message chosen in it, and where
/// playback is.
final class Viewer extends ChangeNotifier {
  Journal _journal = const Journal([]);
  List<JournalEntry> _entries = const [];
  List<JournalConversation> _all = const [];
  List<String> _files = const [];

  /// The names of the files loaded, in the order read.
  List<String> get files => _files;

  /// Every entry loaded, in order.
  List<JournalEntry> get entries => _entries;

  /// Every conversation loaded, in the order it started.
  List<JournalConversation> get all => _all;

  /// Why the last load gave nothing to show; null when it did.
  String? get problem => _problem;
  String? _problem;

  /// Says why nothing could be loaded.
  void fail(String why) {
    _problem = why;
    notifyListeners();
  }

  /// Loads [files] in place of what was loaded: in the order of their
  /// names, which for a writer's files is the order of their days.
  void load(List<JournalFile> files) {
    final sorted = [...files]..sort((a, b) => a.name.compareTo(b.name));
    _entries = [for (final f in sorted) ...parseJournal(f.text)];
    _journal = Journal(_entries);
    _all = _journal.conversations();
    _files = [for (final f in sorted) f.name];
    _first = _entries.isEmpty ? null : _entries.first.at;
    _last = _entries.isEmpty
        ? null
        : _entries.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
    _selected = null;
    _chosenEntries = const [];
    _node = null;
    _playhead = null;
    _playing = false;
    _problem = _entries.isEmpty
        ? 'No journal entry in ${files.map((f) => f.name).join(', ')}'
        : null;
    notifyListeners();
  }

  // --- Filters ----------------------------------------------------------

  String _query = '';
  bool _problemsOnly = false;

  /// Text a conversation's word, principal or id holds.
  String get query => _query;
  set query(String v) {
    if (v == _query) return;
    _query = v;
    notifyListeners();
  }

  /// Only the conversations a call of which was refused, failed or timed
  /// out.
  bool get problemsOnly => _problemsOnly;
  set problemsOnly(bool v) {
    if (v == _problemsOnly) return;
    _problemsOnly = v;
    notifyListeners();
  }

  /// The conversations to list: as filtered, and during playback the ones
  /// begun by then.
  List<JournalConversation> get conversations {
    final q = _query.trim().toLowerCase();
    final at = _playhead;
    return [
      for (final c in _all)
        if ((at == null || !c.started.isAfter(at)) &&
            (!_problemsOnly || hasProblems(c)) &&
            (q.isEmpty ||
                c.origin.word.toLowerCase().contains(q) ||
                c.origin.by.selector.toLowerCase().contains(q) ||
                c.id.toLowerCase().contains(q)))
          c,
    ];
  }

  static bool hasProblems(JournalConversation c) =>
      c.refused + c.failed + c.timedOut > 0;

  // --- The conversation chosen ------------------------------------------

  JournalConversation? _selected;
  List<JournalEntry> _chosenEntries = const [];
  JournalNode? _node;

  JournalConversation? get selected => _selected;

  void select(JournalConversation? c) {
    if (c == _selected) return;
    _selected = c;
    _chosenEntries = c == null
        ? const []
        : _journal.conversation(c.id, epoch: c.epoch);
    _node = null;
    notifyListeners();
  }

  /// The chosen conversation as a tree, as far as playback has come.
  List<JournalNode> get tree {
    final at = _playhead;
    return treeOf(
      at == null
          ? _chosenEntries
          : _chosenEntries.where((e) => !e.at.isAfter(at)),
    );
  }

  /// The message chosen in it.
  JournalNode? get node => _node;
  void choose(JournalNode? n) {
    if (n?.id == _node?.id) return;
    _node = n;
    notifyListeners();
  }

  /// How the message chosen came about, from the first of its
  /// conversation.
  List<JournalEntry> get pathToNode {
    final n = _node;
    return n == null ? const [] : Journal(_chosenEntries).pathTo(n.id);
  }

  // --- Playback ---------------------------------------------------------

  DateTime? _playhead;
  bool _playing = false;
  double _speed = 1;
  bool _skipQuiet = true;

  /// Where playback is; null when not playing back: everything is shown.
  DateTime? get playhead => _playhead;

  bool get playing => _playing;

  /// How many times faster than it happened.
  double get speed => _speed;
  set speed(double v) {
    _speed = v;
    notifyListeners();
  }

  /// Whether a stretch where nothing happened is jumped over.
  bool get skipQuiet => _skipQuiet;
  set skipQuiet(bool v) {
    _skipQuiet = v;
    notifyListeners();
  }

  DateTime? _first, _last;

  /// When the first entry loaded was, and the last.
  DateTime? get first => _first;
  DateTime? get last => _last;

  /// Puts playback at [at], within what was loaded.
  void seek(DateTime at) {
    final f = first, l = last;
    if (f == null || l == null) return;
    _playhead = at.isBefore(f) ? f : (at.isAfter(l) ? l : at);
    notifyListeners();
  }

  void play() {
    if (_entries.isEmpty) return;
    final l = last!;
    if (_playhead == null || !_playhead!.isBefore(l)) _playhead = first;
    _playing = true;
    notifyListeners();
  }

  void pause() {
    _playing = false;
    notifyListeners();
  }

  /// Stops playing back: everything is shown again.
  void stop() {
    _playing = false;
    _playhead = null;
    notifyListeners();
  }

  /// Moves playback on by [wall] of real time, at [speed]; over a quiet
  /// stretch, to just before what happens next, when [skipQuiet].
  void advance(Duration wall) {
    final at = _playhead;
    if (!_playing || at == null) return;
    var next = at.add(wall * _speed);
    if (_skipQuiet) {
      final coming = _nextAfter(at);
      final quiet = const Duration(seconds: 2) * _speed;
      if (coming != null && coming.difference(at) > quiet) {
        next = coming.subtract(const Duration(milliseconds: 300) * _speed);
      }
    }
    final l = last!;
    if (!next.isBefore(l)) {
      next = l;
      _playing = false;
    }
    _playhead = next;
    notifyListeners();
  }

  DateTime? _nextAfter(DateTime at) {
    // Entries are in order: the first one after.
    var lo = 0, hi = _entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_entries[mid].at.isAfter(at)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo < _entries.length ? _entries[lo].at : null;
  }
}

/// How a call ended, in one word: `done`, `refused`, `failed`, `timedOut`,
/// `cancelled`, `lost`; null while it runs.
String? outcomeOf(JournalNode n) => switch (n.end?.call.result) {
  null => null,
  CallDone() => n.end!.call.late ? 'late' : 'done',
  CallRefused() => 'refused',
  CallFailed() => 'failed',
  CallTimedOut() => 'timedOut',
  CallCancelled() => 'cancelled',
  CallLost() => 'lost',
};
