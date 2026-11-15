import 'cause.dart';
import 'compat.dart';
import 'json.dart';
import 'shapes.dart';

DateTime _at(Object? v) => DateTime.parse(v as String);

/// A committed change of one state value (SPEC §7).
final class StateChange {
  /// One committed change: the registry's.
  StateChange({
    required this.seq,
    required this.id,
    required this.state,
    required this.key,
    required Object? value,
    required Object? previous,
    required this.removed,
    required this.cause,
    required this.at,
  }) : _value = value,
       _previous = previous,
       _shape = null;

  StateChange._kept({
    required this.seq,
    required this.id,
    required this.state,
    required this.key,
    required Object? value,
    required Object? previous,
    required this.removed,
    required this.cause,
    required this.at,
    required Shape<Object?> shape,
  }) : _value = value,
       _previous = previous,
       _shape = shape;

  /// [json] as a change.
  factory StateChange.fromJson(Object? json) {
    final m = json as Map;
    return StateChange(
      seq: m['seq'] as int,
      id: m['id'] as String,
      state: m['state'] as String,
      key: m['key'] as String?,
      value: m['value'],
      previous: m['previous'],
      removed: m['removed'] == true,
      cause: Cause.fromJson(m['cause']),
      at: _at(m['at']),
    );
  }

  /// Its place in the registry's total order.
  final int seq;

  /// The id the write was under: a retry with it changes nothing twice.
  final String id;

  /// The word.
  final String state;

  /// The key of a keyed state; null for an unkeyed one.
  final String? key;

  /// The values as the registry keeps them, and the shape it keeps them
  /// by; null: they are JSON.
  final Object? _value;
  final Object? _previous;
  final Shape<Object?>? _shape;
  Object? _valueJson = _unmade;
  Object? _previousJson = _unmade;

  /// The new value, as JSON; null when [removed].
  Object? get value => identical(_valueJson, _unmade)
      ? _valueJson = _jsonOf(_shape, _value)
      : _valueJson;

  /// The value before, as JSON.
  Object? get previous => identical(_previousJson, _unmade)
      ? _previousJson = _jsonOf(_shape, _previous)
      : _previousJson;

  /// The key (or the whole unkeyed value) is gone.
  final bool removed;

  /// Why it is so.
  final Cause cause;

  /// When it committed.
  final DateTime at;

  /// Its JSON.
  Map<String, Object?> toJson({bool payloads = true}) => {
    'seq': seq,
    'id': id,
    'state': state,
    'key': ?key,
    if (payloads && !removed) 'value': value,
    if (removed) 'removed': true,
    if (payloads) 'previous': previous,
    'cause': cause.toJson(),
    'at': at.toUtc().toIso8601String(),
  };

  @override
  String toString() =>
      'StateChange#$seq $state${key == null ? '' : '[$key]'} '
      '${removed ? 'removed' : '= $value'} ($cause)';
}

/// Not made yet: a JSON value is made of a kept one when first asked.
const Object _unmade = _Unmade();

final class _Unmade {
  const _Unmade();
}

/// The JSON of [kept], a value [shape] keeps (as it is, when null), frozen
/// as every value the registry tells is.
Object? _jsonOf(Shape<Object?>? shape, Object? kept) =>
    shape == null || kept == null || shape is JsonValue
    ? kept
    : freezeJson(shape.toJson(kept));

/// A value as the registry keeps it, and the shape it keeps it by (null:
/// it is JSON), its JSON made when first asked, once (SPEC §18): the
/// params of a call and its answer. The package's own.
final class Kept {
  /// A value and the shape it is kept by.
  Kept(this.value, this.shape) : _json = _unmade;

  /// JSON as it is.
  Kept.json(Object? json) : value = json, shape = null, _json = json;

  /// The value as kept; its JSON when [shape] is null.
  final Object? value;

  /// The shape it is kept by; null: it is JSON.
  final Shape<Object?>? shape;
  Object? _json;

  /// Its JSON, frozen.
  Object? get json =>
      identical(_json, _unmade) ? _json = _jsonOf(shape, value) : _json;

  /// The value as [as] has it: itself when it is kept by [as], else its
  /// JSON decoded.
  T asShape<T>(Shape<T> as) =>
      (identical(shape, as) ? value : decodeWith(as, json)) as T;
}

/// A change of a value the registry keeps by [shape]: its JSON is made
/// when someone asks for it (SPEC §18). The package's own.
StateChange keptChange({
  required int seq,
  required String id,
  required String state,
  required String? key,
  required Object? value,
  required Object? previous,
  required bool removed,
  required Cause cause,
  required DateTime at,
  required Shape<Object?> shape,
}) => StateChange._kept(
  seq: seq,
  id: id,
  state: state,
  key: key,
  value: value,
  previous: previous,
  removed: removed,
  cause: cause,
  at: at,
  shape: shape,
);

/// The value of [c] as the registry keeps it, when it keeps it by
/// [shape]; [none] when it is another's or JSON. The package's own.
Object? keptValueOf(StateChange c, Shape<Object?> shape, Object? none) =>
    identical(c._shape, shape) ? c._value : none;

/// A committed fact (SPEC §6.3).
final class FactMessage {
  /// One committed fact: the registry's.
  FactMessage({
    required this.seq,
    required this.id,
    required this.fact,
    required Object? payload,
    required this.cause,
    required this.at,
  }) : _payload = payload,
       _shape = null;

  FactMessage._kept({
    required this.seq,
    required this.id,
    required this.fact,
    required Object? payload,
    required this.cause,
    required this.at,
    required Shape<Object?> shape,
  }) : _payload = payload,
       _shape = shape;

  /// [json] as a fact message.
  factory FactMessage.fromJson(Object? json) {
    final m = json as Map;
    return FactMessage(
      seq: m['seq'] as int,
      id: m['id'] as String,
      fact: m['fact'] as String,
      payload: m['payload'],
      cause: Cause.fromJson(m['cause']),
      at: _at(m['at']),
    );
  }

  /// Its place in the registry's total order.
  final int seq;

  /// The id it was said under: said again under it, it is dropped.
  final String id;

  /// The word.
  final String fact;

  /// The payload as the registry keeps it, and the shape it keeps it by;
  /// null: it is JSON.
  final Object? _payload;
  final Shape<Object?>? _shape;
  Object? _payloadJson = _unmade;

  /// The payload, as JSON.
  Object? get payload => identical(_payloadJson, _unmade)
      ? _payloadJson = _jsonOf(_shape, _payload)
      : _payloadJson;

  /// Why it was said.
  final Cause cause;

  /// When it committed.
  final DateTime at;

  /// Its JSON.
  Map<String, Object?> toJson({bool payloads = true}) => {
    'seq': seq,
    'id': id,
    'fact': fact,
    if (payloads) 'payload': payload,
    'cause': cause.toJson(),
    'at': at.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'Fact#$seq $fact $payload ($cause)';
}

/// A fact whose payload the registry keeps by [shape]: its JSON is made
/// when someone asks for it (SPEC §18). The package's own.
FactMessage keptFact({
  required int seq,
  required String id,
  required String fact,
  required Object? payload,
  required Cause cause,
  required DateTime at,
  required Shape<Object?> shape,
}) => FactMessage._kept(
  seq: seq,
  id: id,
  fact: fact,
  payload: payload,
  cause: cause,
  at: at,
  shape: shape,
);

/// The payload of [m] as the registry keeps it, when it keeps it by
/// [shape]; [none] when it is another's or JSON. The package's own.
Object? keptPayloadOf(FactMessage m, Shape<Object?> shape, Object? none) =>
    identical(m._shape, shape) ? m._payload : none;

/// What a feed gives: a snapshot or a tick (SPEC §12).
sealed class FeedItem {
  const FeedItem();
}

/// Everything committed together (SPEC §7).
final class Tick extends FeedItem {
  /// One tick: everything committed together.
  const Tick({
    required this.epoch,
    required this.from,
    required this.to,
    required this.changes,
    required this.facts,
  });

  /// [json] as a tick.
  factory Tick.fromJson(Object? json) {
    final m = json as Map;
    return Tick(
      epoch: m['epoch'] as String,
      from: m['from'] as int,
      to: m['to'] as int,
      changes: [for (final c in m['changes'] as List) StateChange.fromJson(c)],
      facts: [for (final f in m['facts'] as List) FactMessage.fromJson(f)],
    );
  }

  /// The registry's run it is of.
  final String epoch;

  /// The first and last seq in it.
  final int from;

  /// The seq after its last.
  final int to;

  /// The changes in it, in order.
  final List<StateChange> changes;

  /// The facts in it, in order.
  final List<FactMessage> facts;

  /// Its JSON.
  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'from': from,
    'to': to,
    'changes': [for (final c in changes) c.toJson()],
    'facts': [for (final f in facts) f.toJson()],
  };

  @override
  String toString() => 'Tick $from..$to $changes $facts';
}

/// Every state value at [seq], to start or restart a feed from.
final class Snapshot extends FeedItem {
  /// One snapshot: every value at [seq].
  const Snapshot({
    required this.epoch,
    required this.seq,
    required this.states,
    required this.factsLost,
  });

  /// [json] as a snapshot.
  factory Snapshot.fromJson(Object? json) {
    final m = json as Map;
    return Snapshot(
      epoch: m['epoch'] as String,
      seq: m['seq'] as int,
      states: {
        for (final e in (m['states'] as Map).entries)
          e.key as String: {
            for (final v in e.value as List)
              (v as Map)['key'] as String?: v['value'],
          },
      },
      factsLost: m['factsLost'] == true,
    );
  }

  /// The registry's run it is of.
  final String epoch;

  /// Every value at it.
  final int seq;

  /// State name → key (null for an unkeyed state) → value.
  final Map<String, Map<String?, Object?>> states;

  /// Ticks were missed since the seq the feed was asked from.
  final bool factsLost;

  /// Its JSON.
  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'seq': seq,
    'states': {
      for (final e in states.entries)
        e.key: [
          for (final v in e.value.entries) {'key': ?v.key, 'value': v.value},
        ],
    },
    if (factsLost) 'factsLost': true,
  };
}

/// Why a call was refused (SPEC §9).
enum Refusal {
  /// No word of that name in the catalog.
  unknownCommand,

  /// The params did not pass the word's type.
  invalidParams,

  /// The principal may not read it or call it.
  notPermitted,

  /// The word is not there now: its owner left, or the catalog
  /// moved on.
  unavailable,

  /// A guard said no.
  denied,

  /// The id was given to another call (another command, params or
  /// principal) within the dedup window.
  idConflict,
}

/// Whether one principal can use a word now (SPEC §6.5): it is in the
/// catalog, the principal may read it (a state, a fact) or call it (a
/// command), and a command's owner says it can run.
sealed class WordStatus {
  const WordStatus();

  /// Whether it is [WordReady].
  bool get ready => this is WordReady;

  /// Why it cannot be used now, in a few words for people, as a call's
  /// [CallResult.why]; null when it is ready.
  String? get why => switch (this) {
    WordReady() => null,
    WordMissing() => 'it is not there',
    WordNotPermitted() => 'it is not permitted',
    WordUnavailable(:final why) => why,
    WordMismatch(:final breaks) =>
      'it is not as this code was built against: ${breaks.join('; ')}',
  };
}

/// No word of that name in the catalog: never defined, or its owner left.
final class WordMissing extends WordStatus {
  /// Const constructor.
  const WordMissing();

  @override
  bool operator ==(Object other) => other is WordMissing;

  @override
  int get hashCode => (WordMissing).hashCode;

  @override
  String toString() => 'missing';
}

/// The word is there, but the principal may not read it (its `readers`)
/// or call it (its `callers` deny it).
final class WordNotPermitted extends WordStatus {
  /// Const constructor.
  const WordNotPermitted();

  @override
  bool operator ==(Object other) => other is WordNotPermitted;

  @override
  int get hashCode => (WordNotPermitted).hashCode;

  @override
  String toString() => 'notPermitted';
}

/// A command its owner says cannot run now, and [why].
final class WordUnavailable extends WordStatus {
  /// Const constructor.
  const WordUnavailable(this.why);

  @override
  final String why;

  @override
  bool operator ==(Object other) =>
      other is WordUnavailable && other.why == why;

  @override
  int get hashCode => why.hashCode;

  @override
  String toString() => 'unavailable($why)';
}

/// The word is there, but not as the code asking was built against
/// (SPEC §6.5): its kind or its types changed in a way that breaks a
/// promise (§23.3). [breaks] say where, each as `path: was …, is …`. What
/// uses it would be refused or misread: it is a word to update to, or a
/// version (`.v2`) its owner should have kept beside the old one.
final class WordMismatch extends WordStatus {
  /// Const constructor.
  const WordMismatch(this.breaks);

  /// Where it breaks, each as `path: was …, is …`.
  final List<WordBreak> breaks;

  @override
  bool operator ==(Object other) {
    if (other is! WordMismatch || other.breaks.length != breaks.length) {
      return false;
    }
    for (var i = 0; i < breaks.length; i++) {
      if (other.breaks[i] != breaks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(breaks);

  @override
  String toString() => 'mismatch(${breaks.join('; ')})';
}

/// The word is there and usable by the one asking: in the catalog,
/// permitted, and its owner says it can run.
final class WordReady extends WordStatus {
  /// Const constructor.
  const WordReady();

  @override
  bool operator ==(Object other) => other is WordReady;

  @override
  int get hashCode => (WordReady).hashCode;

  @override
  String toString() => 'ready';
}

/// How a call ended; a typed call ([CommandOf.call]) answers [R].
///
/// Only [CallDone] carries an answer; the other ends are `CallResult<Never>`,
/// so they end a call of any answer type.
sealed class CallResult<R> {
  const CallResult();

  /// [json] as a call's end; an end this side does not know is
  /// `failed`.
  static CallResult<Object?> fromJson(Object? json) {
    final m = json as Map;
    if (m.containsKey('done')) return CallDone(m['value']);
    if (m['refused'] case final String code) {
      final reason = m['reason'] as String? ?? '';
      // A refusal of a newer registry this side does not know: not done,
      // and not to retry, as it would be told if taken for a lost one.
      final refusal = Refusal.values.asNameMap()[code];
      if (refusal == null) return CallFailed('refused ($code): $reason');
      return CallRefused(refusal, reason, guard: m['guard'] as String?);
    }
    if (m.containsKey('failed')) return CallFailed(m['failed'] as String);
    if (m['lost'] case final String id) {
      return CallLost(id, m['reason'] as String? ?? '');
    }
    if (m['timedOut'] == true) return const CallTimedOut();
    if (m['cancelled'] == true) return const CallCancelled();
    return CallFailed('an end this side does not know: $m');
  }

  /// Whether it is [CallDone].
  bool get ok => this is CallDone;

  /// Why it did not end done, in a few words for people: the refusal's
  /// reason, the failure, or that no answer came; null when it is done.
  String? get why => switch (this) {
    CallDone() => null,
    CallRefused(:final why) => why,
    CallFailed(:final error) => '$error',
    CallTimedOut() => 'no answer within its deadline; it may still happen',
    CallCancelled() => 'its caller cancelled it; it may still happen',
    CallLost(:final how) => 'no answer came back ($how); retry with its id',
  };

  /// Its JSON.
  Map<String, Object?> toJson() => switch (this) {
    CallDone(:final value) => {'done': true, 'value': value},
    CallRefused(:final code, :final why, :final guard) => {
      'refused': code.name,
      'reason': why,
      'guard': ?guard,
    },
    CallFailed(:final error) => {'failed': '$error'},
    CallTimedOut() => {'timedOut': true},
    CallCancelled() => {'cancelled': true},
    CallLost(:final id, :final how) => {'lost': id, 'reason': how},
  };
}

/// A call that ended done, with its answer.
final class CallDone<R> extends CallResult<R> {
  /// Const constructor.
  const CallDone(this.value);

  /// The answer; as JSON when the registry answers a call by name.
  final R value;

  @override
  String toString() => 'done($value)';
}

/// A done call whose answer the registry keeps by its shape: [value] is
/// its JSON, made when first asked.
final class _KeptDone extends CallDone<Object?> {
  _KeptDone(this._kept) : super(null);
  final Kept _kept;

  @override
  Object? get value => _kept.json;
}

/// A call done with [answer]. The package's own.
CallDone<Object?> keptDone(Kept answer) =>
    answer.shape == null ? CallDone(answer.value) : _KeptDone(answer);

/// The answer of [r] as the registry keeps it, when it keeps one by a
/// shape. The package's own.
Kept? keptAnswerOf(CallResult<Object?> r) => r is _KeptDone ? r._kept : null;

/// A call the registry refused before its handler began.
final class CallRefused extends CallResult<Never> {
  /// Const constructor.
  const CallRefused(this.code, this.why, {this.guard});

  /// The refusal's kind.
  final Refusal code;

  /// Why it was refused, for people.
  @override
  final String why;

  /// The guard that denied it, for [Refusal.denied].
  final String? guard;

  @override
  String toString() =>
      'refused(${code.name}${guard == null ? '' : ' by $guard'}: $why)';
}

/// A call whose handler threw.
final class CallFailed extends CallResult<Never> {
  /// Const constructor.
  const CallFailed(this.error, [this.stackTrace]);

  /// What the handler threw.
  final Object error;

  /// Where a handler in this process threw [error]: kept for the call's
  /// span in the log, never sent across a connection.
  final StackTrace? stackTrace;

  @override
  String toString() => 'failed($error)';
}

/// No answer within the deadline. It is not a failure: the handler may
/// still finish, and what it does stands. Its end is recorded as a late
/// call record, and a retry with the same id answers it.
final class CallTimedOut extends CallResult<Never> {
  /// Const constructor.
  const CallTimedOut();

  @override
  String toString() => 'timedOut';
}

/// Its caller cancelled it (`cancel:`) and stopped waiting. It is not a
/// failure, nor that it did not happen: cancelled before its handler
/// began, it did not run; after, the handler was told (`expired`), and
/// what it did stands, as when it times out. Its end is recorded as a late
/// call record, and a retry with the same id answers it.
final class CallCancelled extends CallResult<Never> {
  /// Const constructor.
  const CallCancelled();

  @override
  String toString() => 'cancelled';
}

/// No answer came back: the way to the registry broke, or the way from it
/// to the owner serving the call across a connection. Whether the call
/// ran is unknown; a retry with [id] runs it at most once.
final class CallLost extends CallResult<Never> {
  /// Const constructor.
  const CallLost(this.id, this.how);

  /// The call's id: a retry with it runs the call at most once.
  final String id;

  /// How the way broke (`socket closed`); [why] says it for people.
  final String how;

  @override
  String toString() => 'lost($how)';
}

/// A call whose handler began (SPEC §9): it passed every stage. Its end
/// comes as the [CallRecord] of the same id; one that timed out runs on
/// until its late record.
final class CallStarted {
  /// One call whose handler began: the registry's.
  CallStarted({
    required this.id,
    required this.command,
    required Map<String, Object?> params,
    required this.cause,
    required this.started,
    this.ambiguous = false,
  }) : _params = Kept.json(params);

  CallStarted._kept({
    required this.id,
    required this.command,
    required Kept params,
    required this.cause,
    required this.started,
    this.ambiguous = false,
  }) : _params = params;

  /// [json] as a started call.
  factory CallStarted.fromJson(Object? json) {
    final m = json as Map;
    return CallStarted(
      id: m['id'] as String,
      command: m['command'] as String,
      params: (m['params'] as Map? ?? const {}).cast<String, Object?>(),
      cause: Cause.fromJson(m['cause']),
      started: _at(m['started']),
      ambiguous: m['ambiguous'] == true,
    );
  }

  /// The call's id.
  final String id;

  /// The command called.
  final String command;
  final Kept _params;

  /// Its params, as JSON.
  Map<String, Object?> get params => _params.json! as Map<String, Object?>;

  /// Why it was called.
  final Cause cause;

  /// When the call came, as its record says.
  final DateTime started;

  /// The caller reused this ID after its deduplication record was evicted.
  final bool ambiguous;

  /// Its JSON.
  Map<String, Object?> toJson({bool payloads = true}) => {
    'id': id,
    if (ambiguous) 'ambiguous': true,
    'command': command,
    if (payloads) 'params': params,
    'cause': cause.toJson(),
    'started': started.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'Started $command $params ($cause)';
}

/// What the registry still remembers of one conversation (SPEC §4): the
/// calls, changes and facts that followed from one message, however far.
final class Conversation {
  /// One conversation: the registry's.
  const Conversation({
    required this.id,
    required this.calls,
    required this.changes,
    required this.facts,
  });

  /// The id of the message that started it.
  final String id;

  /// The calls in it, in order.
  final List<CallRecord> calls;

  /// The changes in it, in order.
  final List<StateChange> changes;

  /// The facts in it, in order.
  final List<FactMessage> facts;

  /// Whether nothing of it is kept.
  bool get isEmpty => calls.isEmpty && changes.isEmpty && facts.isEmpty;

  /// Its JSON.
  Map<String, Object?> toJson() => {
    'id': id,
    'calls': [for (final c in calls) c.toJson()],
    'changes': [for (final c in changes) c.toJson()],
    'facts': [for (final f in facts) f.toJson()],
  };
}

/// How one principal used a word (SPEC §6.8): its calls and asks, its
/// reads from outside the build, how many of its listeners listen now, and
/// when it last did any of it.
final class WordUse {
  /// One entry of how a word was used.
  const WordUse({
    required this.by,
    required this.calls,
    required this.reads,
    required this.listening,
    required this.last,
  });

  /// Who; a principal's kind alone (`guest`) for the many past
  /// `HostLimits.usersPerWord`.
  final Principal by;

  /// How many calls of it.
  final int calls;

  /// How many reads from outside the build.
  final int reads;

  /// How many of its listeners listen now.
  final int listening;

  /// When it last did any of it.
  final DateTime last;

  /// Its JSON.
  Map<String, Object?> toJson() => {
    'by': by.selector,
    if (calls > 0) 'calls': calls,
    if (reads > 0) 'reads': reads,
    if (listening > 0) 'listening': listening,
    'last': last.toUtc().toIso8601String(),
  };
}

/// A word a principal's code was built against, defined otherwise now
/// (SPEC §6.9): who, the word as its code names it, and every place it
/// breaks, as `WordMismatch` says them. Its [breaks] are empty when it
/// ends: the word keeps its promises again, is gone, or none built
/// against it is there any more.
final class Mismatch {
  /// One mismatch: the registry's.
  const Mismatch(this.by, this.word, this.breaks, {this.from});

  /// Who was built against the word.
  final Principal by;

  /// The word as the code names it.
  final String word;

  /// Where it breaks, each as `WordMismatch` says.
  final List<WordBreak> breaks;

  /// The words package the code took [word] from, when it said
  /// (`notes_words 1.2.0`): which version to look at, or to roll back.
  final String? from;

  /// Its JSON.
  Map<String, Object?> toJson() => {
    'by': by.selector,
    'word': word,
    'from': ?from,
    'breaks': [for (final b in breaks) b.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is Mismatch &&
      other.by == by &&
      other.word == word &&
      other.from == from &&
      sameBreaks(other.breaks, breaks);

  @override
  int get hashCode => Object.hash(by, word, Object.hashAll(breaks));

  @override
  String toString() => breaks.isEmpty
      ? '${by.selector}: $word keeps its promises'
      : '${by.selector} was built against $word'
            '${from == null ? '' : ' of $from'} otherwise: '
            '${breaks.join('; ')}';
}

/// A finished call, for journals (SPEC §9).
final class CallRecord {
  /// One finished call: the registry's.
  CallRecord({
    required this.id,
    required this.command,
    required Map<String, Object?> params,
    required this.cause,
    required this.result,
    required this.started,
    this.ambiguous = false,
    required this.finished,
    this.late = false,
    this.replyResult,
    this.repliedAt,
  }) : _params = Kept.json(params);

  CallRecord._kept({
    required this.id,
    required this.command,
    required Kept params,
    required this.cause,
    required this.result,
    required this.started,
    this.ambiguous = false,
    required this.finished,
    this.late = false,
    this.replyResult,
    this.repliedAt,
  }) : _params = params;

  /// The call's id.
  final String id;

  /// The command called.
  final String command;
  final Kept _params;

  /// Its params, as JSON.
  Map<String, Object?> get params => _params.json! as Map<String, Object?>;

  /// Why it was called.
  final Cause cause;

  /// How it ended.
  final CallResult<Object?> result;

  /// When the call came.
  final DateTime started;

  /// The caller reused this ID after its deduplication record was evicted.
  final bool ambiguous;

  /// When it ended.
  final DateTime finished;

  /// The handler ended after the deadline: the caller was answered
  /// `timedOut`, and this is how the call really ended.
  final bool late;

  /// The result already returned to the caller before this late completion.
  final CallResult<Object?>? replyResult;

  /// When that earlier result was returned.
  final DateTime? repliedAt;

  /// The handler ended after the deadline: the caller was answered
  /// `timedOut`, and this is how the call really ended.
  factory CallRecord.fromJson(Object? json) {
    final m = json as Map;
    return CallRecord(
      id: m['id'] as String,
      command: m['command'] as String,
      params: (m['params'] as Map? ?? const {}).cast<String, Object?>(),
      cause: Cause.fromJson(m['cause']),
      result: CallResult.fromJson(m['result']),
      started: _at(m['started']),
      ambiguous: m['ambiguous'] == true,
      finished: _at(m['finished']),
      late: m['late'] == true,
      replyResult: m['replyResult'] == null
          ? null
          : CallResult.fromJson(m['replyResult']),
      repliedAt: m['repliedAt'] == null ? null : _at(m['repliedAt']),
    );
  }

  /// Its JSON.
  Map<String, Object?> toJson({bool payloads = true}) => {
    'id': id,
    if (ambiguous) 'ambiguous': true,
    'command': command,
    if (payloads) 'params': params,
    'cause': cause.toJson(),
    'result': _resultJson(result, payloads),
    if (replyResult != null) 'replyResult': _resultJson(replyResult!, payloads),
    if (repliedAt != null) 'repliedAt': repliedAt!.toUtc().toIso8601String(),
    'started': started.toUtc().toIso8601String(),
    'finished': finished.toUtc().toIso8601String(),
    if (late) 'late': true,
  };

  @override
  String toString() => 'Call $command $params -> $result ($cause)';
}

/// One entry of the journal (SPEC §9.3): what happened in the system at
/// the level of use, as it happened. A call that began, a call that ended
/// (refused ones too), a fact said, and a state written in a conversation
/// (its cause has a parent), selected independent writes, and payload-free
/// diagnostic decisions. [n] orders the entries of one [epoch].
sealed class JournalEntry {
  const JournalEntry({
    required this.epoch,
    required this.n,
    this.trace,
    this.payloads = true,
  });

  factory JournalEntry.fromJson(Object? json) {
    final m = (json as Map).cast<String, Object?>();
    final epoch = m['epoch']! as String;
    final n = m['n']! as int;
    final trace = m['trace'] as String?;
    return switch (m['kind']) {
      'start' => JournalStart(
        CallStarted.fromJson(m),
        epoch: epoch,
        n: n,
        trace: trace,
        payloads: m['payloads'] != false,
      ),
      'end' => JournalEnd(
        CallRecord.fromJson(m),
        epoch: epoch,
        n: n,
        trace: trace,
        payloads: m['payloads'] != false,
      ),
      'fact' => JournalFact(
        FactMessage.fromJson(m),
        epoch: epoch,
        n: n,
        trace: trace,
        payloads: m['payloads'] != false,
      ),
      'write' => JournalWrite(
        StateChange.fromJson(m),
        epoch: epoch,
        n: n,
        trace: trace,
        payloads: m['payloads'] != false,
      ),
      'diagnostic' => JournalDiagnostic(
        id: m['id'] as String,
        word: m['word'] as String,
        cause: Cause.fromJson(m['cause']),
        at: _at(m['at']),
        event: m['event'] as String,
        data: (m['data'] as Map? ?? const {}).cast<String, Object?>(),
        epoch: epoch,
        n: n,
        trace: trace,
        payloads: false,
      ),
      final k => throw FormatException('no journal entry of kind $k'),
    };
  }

  /// The registry's run it is of.
  final String epoch;

  /// Its place in the journal of [epoch], from 1.
  final int n;

  /// The W3C `traceparent` of the span it is in, or follows from, when
  /// the registry keeps spans (SPEC §9.2): where its telemetry and the
  /// lines logged in it are. Null without one.
  final String? trace;

  /// Whether this recording contains values, rather than metadata alone.
  final bool payloads;

  /// Approximate bytes retained while this entry waits in a bounded queue.
  int get retainedBytes => journalEntryWeight(this);

  /// `start`, `end`, `fact`, `write` or `diagnostic`.
  String get kind;

  /// The word it is of: the command called, the fact said, the state
  /// written.
  String get word;

  /// The id of its message: a call's, a fact's, a change's.
  String get id;

  /// On whose behalf it is.
  Cause get cause;

  /// When it happened.
  DateTime get at;

  /// The conversation it is part of (SPEC §4), as its spans and the
  /// registry's log lines name it too.
  String get conversation => cause.conversationOf(id);

  /// What its conversation started with (SPEC §4): the first message's
  /// word and who; its own for the first.
  Origin get origin => cause.originOf(word);

  /// Its message's JSON, with `epoch`, `n`, `kind`, `conversation`,
  /// `origin` and `trace` beside: one flat object a line of a file holds.
  Map<String, Object?> toJson({bool payloads = true}) => {
    'epoch': epoch,
    'n': n,
    'kind': kind,
    'conversation': conversation,
    'origin': origin.toJson(),
    'trace': ?trace,
    if (!this.payloads || !payloads) 'payloads': false,
    ..._message(payloads: this.payloads && payloads),
  };

  Map<String, Object?> _message({required bool payloads});
}

/// A call whose handler began: it passed every stage.
final class JournalStart extends JournalEntry {
  /// One call begun: the journal's.
  const JournalStart(
    this.call, {
    required super.epoch,
    required super.n,
    super.trace,
    super.payloads,
  });

  /// The call begun.
  final CallStarted call;

  @override
  String get kind => 'start';
  @override
  String get word => call.command;
  @override
  String get id => call.id;
  @override
  Cause get cause => call.cause;
  @override
  DateTime get at => call.started;
  @override
  Map<String, Object?> _message({required bool payloads}) =>
      call.toJson(payloads: payloads);
}

/// A call that ended: answered, failed, timed out or refused (a refused
/// one never began). A late end follows the end of its timeout.
final class JournalEnd extends JournalEntry {
  /// One call that ended: the journal's.
  const JournalEnd(
    this.call, {
    required super.epoch,
    required super.n,
    super.trace,
    super.payloads,
  });

  /// The call ended.
  final CallRecord call;

  @override
  String get kind => 'end';
  @override
  String get word => call.command;
  @override
  String get id => call.id;
  @override
  Cause get cause => call.cause;
  @override
  DateTime get at => call.finished;
  @override
  Map<String, Object?> _message({required bool payloads}) =>
      call.toJson(payloads: payloads);
}

/// A fact said.
final class JournalFact extends JournalEntry {
  /// One fact said: the journal's.
  const JournalFact(
    this.fact, {
    required super.epoch,
    required super.n,
    super.trace,
    super.payloads,
  });

  /// The fact said.
  final FactMessage fact;

  @override
  String get kind => 'fact';
  @override
  String get word => fact.fact;
  @override
  String get id => fact.id;
  @override
  Cause get cause => fact.cause;
  @override
  DateTime get at => fact.at;
  @override
  Map<String, Object?> _message({required bool payloads}) =>
      fact.toJson(payloads: payloads);
}

/// A state written in a conversation: in reply to a call or a fact.
final class JournalWrite extends JournalEntry {
  /// One state written in a conversation: the journal's.
  const JournalWrite(
    this.change, {
    required super.epoch,
    required super.n,
    super.trace,
    super.payloads,
  });

  /// The change written.
  final StateChange change;

  @override
  String get kind => 'write';
  @override
  String get word => change.state;
  @override
  String get id => change.id;
  @override
  Cause get cause => change.cause;
  @override
  DateTime get at => change.at;
  @override
  Map<String, Object?> _message({required bool payloads}) =>
      change.toJson(payloads: payloads);
}

/// Why a state (of a key) is as it is (SPEC §9): its value, its last
/// change still retained, and the messages that led to it, nearest first, as
/// far as they are remembered.
final class Explanation {
  /// One explanation: what asks it is told.
  const Explanation({
    required this.state,
    required this.key,
    required this.value,
    required this.change,
    required this.trail,
    this.forgotten = false,
    this.trailCut = false,
    this.gap,
    this.history = const [],
  });

  /// [json] as an explanation.
  factory Explanation.fromJson(Object? json) {
    final m = json as Map;
    return Explanation(
      state: m['state'] as String,
      key: m['key'] as String?,
      value: m['value'],
      change: m['change'] == null ? null : StateChange.fromJson(m['change']),
      trail: [
        for (final c in m['trail'] as List? ?? const [])
          JournalEntry.fromJson(c),
      ],
      forgotten: m['forgotten'] == true,
      trailCut: m['trailCut'] == true,
      gap: m['gap'] as String?,
      history: [
        for (final c in m['history'] as List? ?? const [])
          StateChange.fromJson(c),
      ],
    );
  }

  /// The word.
  final String state;

  /// The key; null for an unkeyed one.
  final String? key;

  /// The value now.
  final Object? value;

  /// The last change still retained; null when it is older or there was
  /// none.
  final StateChange? change;

  /// [change] is null, and the registry has forgotten a change of this
  /// state (of this key): the change may be older than it retains, rather
  /// than none. A state never written is not forgotten.
  final bool forgotten;

  /// The messages that led to [change], nearest first: at most ten, and
  /// [trailCut] says the trail goes further back than these.
  final List<JournalEntry> trail;

  /// The trail goes on further back than the registry remembers.
  final bool trailCut;

  /// Why the path ends before its verified root, when it does.
  final String? gap;

  /// Selected recent changes of this state/key, across conversations.
  final List<StateChange> history;

  /// Its JSON.
  Map<String, Object?> toJson() => {
    'state': state,
    'key': ?key,
    'value': value,
    if (change case final c?) 'change': c.toJson(),
    if (forgotten) 'forgotten': true,
    if (trail.isNotEmpty) 'trail': [for (final c in trail) c.toJson()],
    if (trailCut) 'trailCut': true,
    if (gap != null) 'gap': gap,
    if (history.isNotEmpty) 'history': [for (final c in history) c.toJson()],
  };
}

/// A call begun, its [params] as the registry keeps them. The package's
/// own.
CallStarted keptStarted({
  required String id,
  required String command,
  required Kept params,
  required Cause cause,
  required DateTime started,
  bool ambiguous = false,
}) => CallStarted._kept(
  id: id,
  command: command,
  params: params,
  cause: cause,
  started: started,
  ambiguous: ambiguous,
);

/// A call ended, its [params] as the registry keeps them. The package's
/// own.
CallRecord keptRecord({
  required String id,
  required String command,
  required Kept params,
  required Cause cause,
  required CallResult<Object?> result,
  required DateTime started,
  bool ambiguous = false,
  required DateTime finished,
  bool late = false,
  CallResult<Object?>? replyResult,
  DateTime? repliedAt,
}) => CallRecord._kept(
  id: id,
  command: command,
  params: params,
  cause: cause,
  result: result,
  started: started,
  ambiguous: ambiguous,
  finished: finished,
  late: late,
  replyResult: replyResult,
  repliedAt: repliedAt,
);

/// A metadata-only observation of a Parlance decision or operation.
final class JournalDiagnostic extends JournalEntry {
  /// An immutable diagnostic entry; data never contains user payloads.
  JournalDiagnostic({
    required this.id,
    required this.word,
    required this.cause,
    required this.at,
    required this.event,
    Map<String, Object?> data = const {},
    required super.epoch,
    required super.n,
    super.trace,
    super.payloads = false,
  }) : data = freezeJson(data)! as Map<String, Object?>;
  @override
  final String id;
  @override
  final String word;
  @override
  final Cause cause;
  @override
  final DateTime at;

  /// The decision or lifecycle stage.
  final String event;

  /// Small, payload-free details recorded when the decision happened.
  final Map<String, Object?> data;
  @override
  String get kind => 'diagnostic';
  @override
  Map<String, Object?> _message({required bool payloads}) => {
    'id': id,
    'word': word,
    'cause': cause.toJson(),
    'at': at.toUtc().toIso8601String(),
    'event': event,
    'data': data,
  };
}

Map<String, Object?> _resultJson(CallResult<Object?> result, bool payloads) =>
    result is CallDone && !payloads ? {'done': true} : result.toJson();

/// Weighs retained values in their native representation without encoding them.
int journalEntryWeight(JournalEntry entry) {
  int kept(Kept p) => p.shape?.weigh(p.value) ?? jsonWeight(p.value);
  int value(Shape<Object?>? shape, Object? v) =>
      v == null ? 8 : shape?.weigh(v) ?? jsonWeight(v);
  int result(CallResult<Object?> r) => switch (r) {
    _KeptDone(:final _kept) => entry.payloads ? kept(_kept) : 16,
    CallDone(:final value) => entry.payloads ? jsonWeight(value) : 16,
    CallFailed(:final error, :final stackTrace) =>
      jsonWeight('$error') + jsonWeight(stackTrace?.toString()),
    CallRefused(:final why, :final guard) =>
      jsonWeight(why) + jsonWeight(guard),
    CallLost(:final id, :final how) => jsonWeight(id) + jsonWeight(how),
    CallTimedOut() || CallCancelled() => 16,
  };
  final base =
      256 +
      2 *
          (entry.id.length +
              entry.word.length +
              entry.cause.toJson().toString().length);
  return base +
      switch (entry) {
        JournalStart(:final call) => entry.payloads ? kept(call._params) : 0,
        JournalEnd(:final call) =>
          (entry.payloads ? kept(call._params) : 0) +
              result(call.result) +
              (call.replyResult == null ? 0 : result(call.replyResult!)),
        JournalFact(:final fact) =>
          entry.payloads ? value(fact._shape, fact._payload) : 0,
        JournalWrite(:final change) =>
          entry.payloads
              ? value(change._shape, change._value) +
                    value(change._shape, change._previous)
              : 0,
        JournalDiagnostic(:final data) => jsonWeight(data),
      };
}
