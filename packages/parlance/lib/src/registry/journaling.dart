// Internal to the library: what these files show is not a promise
// Documented surface lives in schema.dart and app.dart.
// ignore_for_file: public_member_api_docs
import 'dart:async';

import 'cause.dart';
import 'messages.dart';
import 'tracing.dart';

/// What happened, at the level of use, as the registry tells it (SPEC
/// §9.3): every call as it begins and as it ends, refused ones too, every
/// fact said, and every state written in a conversation, in one order,
/// each in the trace it is in. It keeps nothing, and makes nothing while
/// no one listens.
final class Journaling {
  Journaling({required this.epoch, required CallTraces traces})
    : _traces = traces;

  final String epoch;
  final CallTraces _traces;

  /// Synchronous: an entry is with its listeners as it happens, in order,
  /// so a writer keeps all of it, however the registry goes after.
  final StreamController<JournalEntry> _out = StreamController.broadcast(
    sync: true,
  );
  int _n = 0;

  Stream<JournalEntry> get stream => _out.stream;

  /// Whether anyone listens: else nothing of it is made.
  bool get on => _out.hasListener;

  void _write(
    JournalEntry Function(int n, String? trace) entry,
    String id,
    Cause cause,
  ) {
    if (_out.isClosed) return;
    _out.add(entry(++_n, _traces.traceOf(id, cause)));
  }

  /// A call whose handler begins.
  void started(CallStarted s) {
    if (!on) return;
    _write(
      (n, trace) => JournalStart(s, epoch: epoch, n: n, trace: trace),
      s.id,
      s.cause,
    );
  }

  /// A call that ended, refused ones too.
  void ended(CallRecord r) {
    if (!on) return;
    _write(
      (n, trace) => JournalEnd(r, epoch: epoch, n: n, trace: trace),
      r.id,
      r.cause,
    );
  }

  /// [t]'s facts, and its writes in a conversation, in the order they were
  /// made.
  void tick(Tick t) {
    if (!on) return;
    final writes = [
      for (final c in t.changes)
        if (c.cause.parent != null) c,
    ];
    var w = 0, f = 0;
    while (w < writes.length || f < t.facts.length) {
      if (f >= t.facts.length ||
          (w < writes.length && writes[w].seq < t.facts[f].seq)) {
        final c = writes[w++];
        _write(
          (n, trace) => JournalWrite(c, epoch: epoch, n: n, trace: trace),
          c.id,
          c.cause,
        );
      } else {
        final m = t.facts[f++];
        _write(
          (n, trace) => JournalFact(m, epoch: epoch, n: n, trace: trace),
          m.id,
          m.cause,
        );
      }
    }
  }

  Future<void> close() => _out.close();
}
