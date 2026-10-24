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
}

/// How a call ended.
sealed class CallResult {
  const CallResult();

  factory CallResult.fromJson(Object? json) {
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
  };
}

final class CallDone extends CallResult {
  const CallDone([this.value]);

  final Object? value;

  @override
  String toString() => 'done($value)';
}

final class CallRefused extends CallResult {
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

final class CallFailed extends CallResult {
  const CallFailed(this.error);

  final Object error;

  @override
  String toString() => 'failed($error)';
}

final class CallTimedOut extends CallResult {
  const CallTimedOut();

  @override
  String toString() => 'timedOut';
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
  });

  final String id;
  final String command;
  final Map<String, Object?> params;
  final Cause cause;
  final CallResult result;

  /// The guards that denied it and that the caller overrode.
  final List<String> overridden;

  /// The before hooks that ran, in order.
  final List<String> hooks;

  /// The registry made it to apply a layer.
  final bool layerDispatch;
  final DateTime started;
  final DateTime finished;

  @override
  String toString() => 'Call $command $params -> $result ($cause)';
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
