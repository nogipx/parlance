// Internal to the library: what these files show is not a promise
// Documented surface lives in schema.dart and app.dart.
// ignore_for_file: public_member_api_docs
import 'dart:async';
import 'dart:collection';

import 'package:rpc_dart/internal.dart'
    show BoundedStreamBridge, StreamBufferLimits, StreamBridgeStats;

import 'cause.dart';
import 'messages.dart';
import 'tracing.dart';
import 'streams.dart';

/// What happened, at the level of use, as the registry tells it (SPEC
/// §9.3): every call as it begins and as it ends, refused ones too, every
/// fact said, and every state written in a conversation, in one order,
/// plus bounded decision metadata, each in its trace. Paused and reentrant
/// delivery is bounded; no listener means no entries.
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
  final Queue<(JournalEntry, int)> _pending = Queue();
  int _pendingBytes = 0;
  int _dropped = 0;
  bool _emitting = false;
  bool _closed = false;

  final Map<BoundedStreamBridge<JournalEntry>, StreamBridgeStats> _listeners =
      {};

  Stream<JournalEntry> get stream => Stream.multi((out) {
    if (_closed) {
      out.closeSync();
      return;
    }
    final stats = StreamBridgeStats();
    late final BoundedStreamBridge<JournalEntry> bridge;
    bridge = BoundedStreamBridge<JournalEntry>(
      source: () => _out.stream,
      pauseSource: false,
      deferStart: false,
      limits: const StreamBufferLimits(items: 64, bytes: 4 << 20),
      stats: stats,
      weigh: (e) => e.retainedBytes,
      overflowError: () => const StreamFailure(
        StreamFailureCode.resourceExhausted,
        'journal listener exceeded its pending limit',
      ),
      onClosed: (_, _, _) => _listeners.remove(bridge),
    );
    _listeners[bridge] = stats;
    final sub = bridge.stream.listen(
      out.addSync,
      onError: out.addErrorSync,
      onDone: out.closeSync,
    );
    out.onPause = sub.pause;
    out.onResume = sub.resume;
    out.onCancel = sub.cancel;
  }, isBroadcast: true);

  final Set<Set<String>> _stateFilters = {};

  /// Registers an independent-write capture filter for one recorder's lifetime.
  void Function() capture(Set<String> words) {
    final filter = Set<String>.unmodifiable(words);
    _stateFilters.add(filter);
    return () => _stateFilters.remove(filter);
  }

  /// Records an already-made payload-free observation in journal order.
  void diagnostic(JournalDiagnostic entry) {
    if (!on) return;
    _write(
      (n, trace) => JournalDiagnostic(
        id: entry.id,
        word: entry.word,
        cause: entry.cause,
        at: entry.at,
        event: entry.event,
        data: entry.data,
        epoch: epoch,
        n: n,
        trace: trace,
      ),
      entry.id,
      entry.cause,
    );
  }

  /// Whether anyone listens: else nothing of it is made.
  bool get on => _out.hasListener;

  void _write(
    JournalEntry Function(int n, String? trace) entry,
    String id,
    Cause cause,
  ) {
    if (_closed || _out.isClosed) return;
    final made = entry(++_n, _traces.traceOf(id, cause));
    if (_emitting) {
      final bytes = made.retainedBytes;
      if (_pending.length >= 64 || _pendingBytes + bytes > (4 << 20)) {
        _dropped++;
        return;
      }
      _pending.add((made, bytes));
      _pendingBytes += bytes;
      return;
    }
    _emitting = true;
    try {
      _out.add(made);
      while (!_closed) {
        if (_pending.isNotEmpty) {
          final (next, bytes) = _pending.removeFirst();
          _pendingBytes -= bytes;
          _out.add(next);
          continue;
        }
        if (_dropped == 0) break;
        final dropped = _dropped;
        _dropped = 0;
        _out.add(
          JournalDiagnostic(
            id: 'gap-$_n',
            word: 'parlance.capture',
            cause: const Cause(Principal.system),
            at: made.at,
            event: 'capture.gap',
            data: {'dropped': dropped},
            epoch: epoch,
            n: ++_n,
          ),
        );
      }
    } finally {
      _emitting = false;
      _pending.clear();
      _pendingBytes = 0;
    }
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
        if (c.cause.parent != null ||
            _stateFilters.any((words) => words.contains(c.state)))
          c,
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

  Future<void> close() {
    _stateFilters.clear();
    _closed = true;
    for (final entry in _listeners.entries.toList()) {
      if (entry.value.pendingItems > 0) {
        entry.key.fail(
          const StreamFailure(
            StreamFailureCode.cancelled,
            'journal ended; unread pending entries were discarded',
          ),
        );
      } else {
        entry.key.close();
      }
    }
    _listeners.clear();
    _pending.clear();
    _pendingBytes = 0;
    return _emitting
        ? Future<void>.microtask(() => _out.close())
        : _out.close();
  }
}
