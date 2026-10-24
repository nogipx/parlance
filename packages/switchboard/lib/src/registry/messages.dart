import 'cause.dart';

DateTime _at(Object? v) => DateTime.parse(v as String);

/// A committed change of one state value (SPEC §7).
final class StateChange {
  const StateChange({
    required this.seq,
    required this.id,
    required this.state,
    required this.key,
    required this.value,
    required this.previous,
    required this.removed,
    required this.cause,
    required this.at,
  });

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

  final int seq;
  final String id;
  final String state;

  /// The key of a keyed state; null for an unkeyed one.
  final String? key;

  /// The new value; null when [removed].
  final Object? value;
  final Object? previous;

  /// The key (or the whole unkeyed value) is gone.
  final bool removed;
  final Cause cause;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'seq': seq,
    'id': id,
    'state': state,
    'key': ?key,
    if (!removed) 'value': value,
    if (removed) 'removed': true,
    'previous': previous,
    'cause': cause.toJson(),
    'at': at.toUtc().toIso8601String(),
  };

  @override
  String toString() =>
      'StateChange#$seq $state${key == null ? '' : '[$key]'} '
      '${removed ? 'removed' : '= $value'} ($cause)';
}

/// A committed fact (SPEC §6.3).
final class FactMessage {
  const FactMessage({
    required this.seq,
    required this.id,
    required this.fact,
    required this.payload,
    required this.cause,
    required this.at,
  });

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

  final int seq;
  final String id;
  final String fact;
  final Object? payload;
  final Cause cause;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'seq': seq,
    'id': id,
    'fact': fact,
    'payload': payload,
    'cause': cause.toJson(),
    'at': at.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'Fact#$seq $fact $payload ($cause)';
}

/// What a feed gives: a snapshot or a tick (SPEC §12).
sealed class FeedItem {
  const FeedItem();
}

/// Everything committed together (SPEC §7).
final class Tick extends FeedItem {
  const Tick({
    required this.epoch,
    required this.from,
    required this.to,
    required this.changes,
    required this.facts,
  });

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

  final String epoch;

  /// The first and last seq in it.
  final int from;
  final int to;
  final List<StateChange> changes;
  final List<FactMessage> facts;

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
  const Snapshot({
    required this.epoch,
    required this.seq,
    required this.states,
    required this.factsLost,
  });

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

  final String epoch;
  final int seq;

  /// State name → key (null for an unkeyed state) → value.
  final Map<String, Map<String?, Object?>> states;

  /// Ticks were missed since the seq the feed was asked from.
  final bool factsLost;

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
  unknownCommand,
  invalidParams,
  notPermitted,
  unavailable,
  denied,

  /// The id was given to another call (another command, params or
  /// principal) within the dedup window.
  idConflict,
}

/// How a call ended; a typed call ([CommandOf.call]) answers [R].
///
/// Only [CallDone] carries an answer; the other ends are `CallResult<Never>`,
/// so they end a call of any answer type.
sealed class CallResult<R> {
  const CallResult();

  static CallResult<Object?> fromJson(Object? json) {
    final m = json as Map;
    if (m.containsKey('done')) return CallDone(m['value']);
    if (m['refused'] case final String code) {
      return CallRefused(
        Refusal.values.byName(code),
        m['reason'] as String? ?? '',
        guard: m['guard'] as String?,
        overridable: m['overridable'] == true,
      );
    }
    if (m.containsKey('failed')) return CallFailed(m['failed'] as String);
    if (m['lost'] case final String id) {
      return CallLost(id, m['reason'] as String? ?? '');
    }
    return const CallTimedOut();
  }

  bool get ok => this is CallDone;

  Map<String, Object?> toJson() => switch (this) {
    CallDone(:final value) => {'done': true, 'value': value},
    CallRefused(:final code, :final reason, :final guard, :final overridable) =>
      {
        'refused': code.name,
        'reason': reason,
        'guard': ?guard,
        if (overridable) 'overridable': true,
      },
    CallFailed(:final error) => {'failed': '$error'},
    CallTimedOut() => {'timedOut': true},
    CallLost(:final id, :final reason) => {'lost': id, 'reason': reason},
  };
}

final class CallDone<R> extends CallResult<R> {
  const CallDone(this.value);

  final R value;

  @override
  String toString() => 'done($value)';
}

final class CallRefused extends CallResult<Never> {
  const CallRefused(
    this.code,
    this.reason, {
    this.guard,
    this.overridable = false,
  });

  final Refusal code;
  final String reason;

  /// The guard that denied it, for [Refusal.denied].
  final String? guard;

  /// A guard's denial that a principal allowed to override may override.
  final bool overridable;

  @override
  String toString() =>
      'refused(${code.name}${guard == null ? '' : ' by $guard'}: $reason)';
}

final class CallFailed extends CallResult<Never> {
  const CallFailed(this.error);

  final Object error;

  @override
  String toString() => 'failed($error)';
}

/// No answer within the deadline. It is not a failure: the handler may
/// still finish, and what it does stands. Its end is recorded as a late
/// call record, and a retry with the same id answers it.
final class CallTimedOut extends CallResult<Never> {
  const CallTimedOut();

  @override
  String toString() => 'timedOut';
}

/// No answer came back: the way to the registry broke. Whether the call
/// ran is unknown; a retry with [id] runs it at most once.
final class CallLost extends CallResult<Never> {
  const CallLost(this.id, this.reason);
  final String id;
  final String reason;

  @override
  String toString() => 'lost($reason)';
}

/// A finished call, for journals (SPEC §9).
final class CallRecord {
  const CallRecord({
    required this.id,
    required this.command,
    required this.params,
    required this.cause,
    required this.result,
    required this.overridden,
    required this.hooks,
    required this.layerDispatch,
    required this.started,
    required this.finished,
    this.late = false,
  });

  final String id;
  final String command;
  final Map<String, Object?> params;
  final Cause cause;
  final CallResult<Object?> result;

  /// The guards that denied it and that the caller overrode.
  final List<String> overridden;

  /// The before hooks that ran, in order.
  final List<String> hooks;

  /// The registry made it to apply a layer.
  final bool layerDispatch;
  final DateTime started;
  final DateTime finished;

  /// The handler ended after the deadline: the caller was answered
  /// `timedOut`, and this is how the call really ended.
  final bool late;

  factory CallRecord.fromJson(Object? json) {
    final m = json as Map;
    return CallRecord(
      id: m['id'] as String,
      command: m['command'] as String,
      params: (m['params'] as Map? ?? const {}).cast<String, Object?>(),
      cause: Cause.fromJson(m['cause']),
      result: CallResult.fromJson(m['result']),
      overridden: [for (final g in m['overridden'] as List? ?? const []) '$g'],
      hooks: [for (final h in m['hooks'] as List? ?? const []) '$h'],
      layerDispatch: m['layerDispatch'] == true,
      started: _at(m['started']),
      finished: _at(m['finished']),
      late: m['late'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'command': command,
    'params': params,
    'cause': cause.toJson(),
    'result': result.toJson(),
    if (overridden.isNotEmpty) 'overridden': overridden,
    if (hooks.isNotEmpty) 'hooks': hooks,
    if (layerDispatch) 'layerDispatch': true,
    'started': started.toUtc().toIso8601String(),
    'finished': finished.toUtc().toIso8601String(),
    if (late) 'late': true,
  };

  @override
  String toString() => 'Call $command $params -> $result ($cause)';
}

/// One layer as it stands (SPEC §8): what holds which state at which value.
final class LayerInfo {
  const LayerInfo({
    required this.id,
    required this.state,
    required this.key,
    required this.value,
    required this.owner,
    required this.by,
    required this.priority,
    required this.top,
    this.expiresAt,
    this.claimed = true,
  });

  factory LayerInfo.fromJson(Object? json) {
    final m = json as Map;
    return LayerInfo(
      id: m['id'] as String,
      state: m['state'] as String,
      key: m['key'] as String?,
      value: m['value'],
      owner: m['owner'] as String,
      by: Principal.fromJson(m['by']),
      priority: m['priority'] as int? ?? 0,
      top: m['top'] == true,
      expiresAt: m['expiresAt'] == null ? null : _at(m['expiresAt']),
      claimed: m['claimed'] != false,
    );
  }

  final String id;
  final String state;
  final String? key;
  final Object? value;
  final String owner;
  final Principal by;
  final int priority;

  /// Its value is the one in force.
  final bool top;
  final DateTime? expiresAt;

  /// False for a layer restored after a restart that its owner has not
  /// claimed yet.
  final bool claimed;

  Map<String, Object?> toJson() => {
    'id': id,
    'state': state,
    'key': ?key,
    'value': value,
    'owner': owner,
    'by': by.toJson(),
    'priority': priority,
    'top': top,
    if (expiresAt case final at?) 'expiresAt': at.toUtc().toIso8601String(),
    if (!claimed) 'claimed': false,
  };

  @override
  String toString() =>
      'Layer $id of $owner on $state${key == null ? '' : '[$key]'} = $value';
}

/// Why a state (of a key) is as it is (SPEC §9): its value, its last
/// change still retained, the calls that led to it, nearest first, as far
/// as they are remembered, and the layers holding it.
final class Explanation {
  const Explanation({
    required this.state,
    required this.key,
    required this.value,
    required this.change,
    required this.trail,
    required this.layers,
    this.forgotten = false,
    this.trailCut = false,
  });

  factory Explanation.fromJson(Object? json) {
    final m = json as Map;
    return Explanation(
      state: m['state'] as String,
      key: m['key'] as String?,
      value: m['value'],
      change: m['change'] == null ? null : StateChange.fromJson(m['change']),
      trail: [
        for (final c in m['trail'] as List? ?? const []) CallRecord.fromJson(c),
      ],
      layers: [
        for (final l in m['layers'] as List? ?? const []) LayerInfo.fromJson(l),
      ],
      forgotten: m['forgotten'] == true,
      trailCut: m['trailCut'] == true,
    );
  }

  final String state;
  final String? key;
  final Object? value;

  /// The last change still retained; null when it is older or there was
  /// none.
  final StateChange? change;

  /// [change] is null, and the registry has forgotten ticks: the change
  /// may be older than it retains, rather than none.
  final bool forgotten;

  /// The calls that led to [change], nearest first.
  final List<CallRecord> trail;

  /// The trail goes on further back than the registry remembers.
  final bool trailCut;
  final List<LayerInfo> layers;

  Map<String, Object?> toJson() => {
    'state': state,
    'key': ?key,
    'value': value,
    if (change case final c?) 'change': c.toJson(),
    if (forgotten) 'forgotten': true,
    if (trail.isNotEmpty) 'trail': [for (final c in trail) c.toJson()],
    if (trailCut) 'trailCut': true,
    if (layers.isNotEmpty) 'layers': [for (final l in layers) l.toJson()],
  };
}

/// Why a layer went away or did not apply (SPEC §8).
enum LayerOutcome {
  /// Its owner removed it.
  removed,

  /// An explicit set cleared it.
  overridden,

  /// Its time ran out.
  expired,

  /// Nobody claimed it after a restart.
  unclaimed,

  /// Its state or setter is gone.
  orphaned,

  /// The dispatch of its value was refused; the layer stays.
  refused,
}

/// Something that happened to a layer, for its owner.
final class LayerEvent {
  const LayerEvent({
    required this.layer,
    required this.owner,
    required this.state,
    required this.key,
    required this.outcome,
    this.reason,
  });

  factory LayerEvent.fromJson(Object? json) {
    final m = json as Map;
    return LayerEvent(
      layer: m['layer'] as String,
      owner: m['owner'] as String,
      state: m['state'] as String,
      key: m['key'] as String?,
      outcome: LayerOutcome.values.byName(m['outcome'] as String),
      reason: m['reason'] as String?,
    );
  }

  final String layer;
  final String owner;
  final String state;
  final String? key;
  final LayerOutcome outcome;
  final String? reason;

  Map<String, Object?> toJson() => {
    'layer': layer,
    'owner': owner,
    'state': state,
    'key': ?key,
    'outcome': outcome.name,
    'reason': ?reason,
  };

  @override
  String toString() =>
      'LayerEvent $layer of $owner on $state${key == null ? '' : '[$key]'}: '
      '${outcome.name}${reason == null ? '' : ' ($reason)'}';
}
