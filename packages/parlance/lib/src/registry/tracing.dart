import 'dart:collection';

import 'package:rpc_dart/logger.dart';

import 'cause.dart';
import 'messages.dart';

/// The span of a call with no log: `LogScope.noop`'s, ended and keeping
/// nothing.
final LogSpanHandle noSpan = LogScope.noop.startSpan('');

/// The registry's calls as spans in its log (SPEC §9.2): each call its
/// handler serves is a span, a child of the span of the call it follows
/// from while that one runs, else the first of a trace linked to it. What
/// a call wrote and said is an event of its span. Nothing is kept while
/// the registry has no log.
final class CallTraces {
  CallTraces(this._log, {required this.on, required int keep}) : _keep = keep;

  final LogScope _log;

  /// Whether the registry was given a log to trace in.
  final bool on;

  /// How many traces of messages it keeps: as many as ticks are retained.
  final int _keep;

  /// The spans of the calls whose handlers run now, by call id.
  final Map<String, LogSpanHandle> _spans = {};

  /// The trace of each message a span may follow from once its own span is
  /// over: facts said in a call's span, calls that ended.
  final LinkedHashMap<String, String> _traces = LinkedHashMap();

  /// The trace a message is in: its own span's, running or ended, else
  /// the one of what it follows from.
  String? traceOf(String id, Cause cause) {
    if (!on) return null;
    final parent = cause.parent;
    return _spans[id]?.traceparent ??
        _traces[id] ??
        (parent == null
            ? null
            : _spans[parent]?.traceparent ?? _traces[parent]);
  }

  void _remember(String message, String traceparent) {
    _traces[message] = traceparent;
    if (_traces.length > _keep) _traces.remove(_traces.keys.first);
  }

  /// Opens the span of a call its handler begins to serve: a child of the
  /// span of the call it follows from, if that one still runs, else the
  /// first of a trace named by what it follows from, or by itself.
  LogSpanHandle open(
    String id,
    String command,
    Kept params,
    Cause cause, {
    required bool query,
  }) {
    if (!on) return noSpan;
    final span = switch (_spans[cause.parent]) {
      final parent? => parent.startSpan(command),
      // What it follows from is over (a fact said, a call that ended): it
      // starts a trace of its own, linked to that one.
      null => _log.startSpan(command, links: [?_traces[cause.parent]]),
    };
    // A span with no id is one the log keeps none of (spans off, nothing
    // reading it): nothing more is made for it.
    if (span.spanId.isEmpty) return span;
    span.addData({
      'call': id,
      'parent': ?cause.parent,
      // The conversation it is part of: what a trace, one request, does
      // not tell, a message come in and what it led to minutes after.
      'conversation': cause.conversationOf(id),
      'by': cause.by.selector,
      'origin': cause.originOf(command).word,
      'originBy': cause.originOf(command).by.selector,
      if (query) 'query': true,
      if (_log.isDebug) 'params': params.json!,
    });
    _spans[id] = span;
    return span;
  }

  /// Ends the span of call [id], as [r] ended it.
  void close(
    String id,
    LogSpanHandle span,
    CallResult<Object?> r, {
    bool late = false,
    bool query = false,
  }) {
    if (!on) return;
    _spans.remove(id);
    // A query leads to nothing that could follow from it: its trace would
    // only push out the ones a later call may link.
    if (!query) {
      if (span.traceparent case final tp?) _remember(id, tp);
    }
    if (late) span.addData({'late': true});
    switch (r) {
      case CallFailed(:final error):
        span.end(status: LogSpanStatus.error, error: error);
      case _:
        span.end();
    }
  }

  /// A fact of [t] said in a call's span, or following a message that had
  /// one, is in that trace: what answers it links there.
  void said(Tick t) {
    if (!on) return;
    for (final f in t.facts) {
      final p = f.cause.parent;
      if (_spans[p]?.traceparent ?? _traces[p] case final tp?) {
        _remember(f.id, tp);
      }
    }
  }

  /// Each write and fact of [t] made in reply to a call, as an event of
  /// the call's span (at debug).
  void events(Tick t) {
    if (_spans.isEmpty || !_log.isDebug) return;
    for (final c in t.changes) {
      _spans[c.cause.parent]?.event(
        c.removed ? 'removed' : 'wrote',
        level: RpcLogLevel.debug,
        data: {
          'state': c.state,
          'key': ?c.key,
          'by': c.cause.by.selector,
          'seq': c.seq,
        },
      );
    }
    for (final f in t.facts) {
      _spans[f.cause.parent]?.event(
        'said',
        level: RpcLogLevel.debug,
        data: {'fact': f.fact, 'by': f.cause.by.selector, 'seq': f.seq},
      );
    }
  }
}
