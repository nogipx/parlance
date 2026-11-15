// Internal to the library: what these files show is not a promise
// Documented surface lives in schema.dart and app.dart.
// ignore_for_file: public_member_api_docs
import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';

import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/messages.dart';
import 'contract.dart';

/// Whether a request that ended with [status] was answered by the session
/// itself, refusing it (SPEC §14: a word not there, a value of the wrong
/// type, what the principal may not do, a name taken, too much asked):
/// any other status may be the way breaking, here or there, and whether
/// the request was done is not known.
bool answeredBySession(RpcStatus status) => switch (status) {
  RpcStatus.permissionDenied ||
  RpcStatus.invalidArgument ||
  RpcStatus.notFound ||
  RpcStatus.alreadyExists ||
  RpcStatus.resourceExhausted => true,
  _ => false,
};

/// What a remote feed gives (SPEC §12, §14).
sealed class RemoteFeed {
  const RemoteFeed();
}

/// The catalog as the session's principal sees it (`describeFor`); first,
/// and on every change.
final class RemoteCatalog extends RemoteFeed {
  const RemoteCatalog(this.json);
  final Map<String, Object?> json;
}

/// An item of the feed this client cannot read ([kind], what it said it
/// was): a host's defect, not one of a newer protocol, which is skipped.
final class RemoteMalformed extends RemoteFeed {
  const RemoteMalformed(this.kind, this.error);
  final String kind;
  final Object error;
}

final class RemoteSnapshot extends RemoteFeed {
  const RemoteSnapshot(this.snapshot, {this.subscription = 0});
  final Snapshot snapshot;

  /// The session's subscription it follows ([ParlanceClient.subscribe]).
  final int subscription;
}

final class RemoteTick extends RemoteFeed {
  const RemoteTick(this.tick);
  final Tick tick;
}

/// The commands that cannot run now, and why: after a tick that changed
/// it, the whole set (the catalog item carries it too).
final class RemoteUnavailable extends RemoteFeed {
  const RemoteUnavailable(this.unavailable);
  final Map<String, String> unavailable;
}

/// The host ended the session, the connection still up ([why]): the last
/// item of its feed. The part across does not join again.
final class RemoteEnded extends RemoteFeed {
  const RemoteEnded(this.why);
  final String why;
}

/// The session subscribed ([ParlanceClient.subscribe]): the values of the
/// states its feed carries now and did not, and which it carries ([keep];
/// null for all). The ticks after keep them.
final class RemoteValues extends RemoteFeed {
  const RemoteValues(this.subscription, this.states, this.keep);

  factory RemoteValues.fromJson(Map<String, Object?> m) =>
      RemoteValues(m['subscription'] as int, {
        for (final e in (m['states'] as Map).entries)
          e.key as String: {
            for (final v in e.value as List)
              (v as Map)['key'] as String?: v['value'],
          },
      }, (m['keep'] as List?)?.cast<String>().toSet());

  final int subscription;

  /// State name → key (null for an unkeyed state) → value.
  final Map<String, Map<String?, Object?>> states;
  final Set<String>? keep;
}

/// The registry as a remote participant uses it, over its side of a peer
/// connection.
final class ParlanceClient {
  ParlanceClient(
    RpcPeerEndpoint endpoint, {
    this.timeout = const Duration(seconds: 10),
  }) : _caller = ParlanceContractPeerCaller(endpoint);

  final ParlanceContractPeerCaller _caller;
  Set<String>? _hostFeatures;

  /// The deadline of a request the registry answers at once (describe,
  /// why, recent facts), without a context of its own.
  /// A [call] has none: the registry bounds it itself, its hooks and its
  /// handler, and answers a timeout.
  final Duration timeout;

  RpcContext _ctx(RpcContext? c) =>
      c ?? RpcContext.empty().withTimeout(timeout);

  Future<Map<String, Object?>> describe({RpcContext? context}) async {
    final json = (await _caller.describe(
      const RpcNull(),
      context: _ctx(context),
    )).json;
    _hostFeatures = (json['features'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    return json;
  }

  Future<void> _requireCausalDiagnostics(RpcContext? context) async {
    if (_hostFeatures == null) await describe(context: context);
    if (!_hostFeatures!.contains('causalDiagnostics')) {
      throw UnsupportedError('host does not speak causalDiagnostics');
    }
  }

  /// An independent data subscription, without a lifetime timeout.
  Future<WireJson> uploadData(Stream<WireJson> requests, RpcContext context) =>
      _caller.uploadData(requests, context: context);

  Stream<WireJson> exchangeData(
    Stream<WireJson> requests,
    RpcContext context,
  ) => _caller.exchangeData(requests, context: context);

  Stream<WireJson> openData(Map<String, Object?> request) =>
      _caller.openData(WireJson(request), context: RpcContext.empty());

  /// The feed: the catalog, then a snapshot or the ticks after [since] of
  /// [epoch], then live. Cancel the subscription to end it.
  Stream<RemoteFeed> feed({String? epoch, int? since, RpcContext? context}) =>
      _caller
          .feed(
            WireFeedRequest(epoch: epoch, since: since),
            context: context,
          )
          .map((i) {
            try {
              return _item(i);
            } on Object catch (e) {
              return RemoteMalformed(i.kind, e);
            }
          })
          .where((i) => i != null)
          .cast();

  static RemoteFeed? _item(WireFeedItem i) => switch (i.kind) {
    'catalog' => RemoteCatalog(i.json),
    'snapshot' => RemoteSnapshot(
      Snapshot.fromJson(i.json),
      subscription: i.json['subscription'] as int? ?? 0,
    ),
    'values' => RemoteValues.fromJson(i.json),
    'unavailable' => RemoteUnavailable(
      Map<String, String>.from(i.json['unavailable']! as Map),
    ),
    'tick' => RemoteTick(Tick.fromJson(i.json)),
    'ended' => RemoteEnded(i.json['why'] as String? ?? ''),
    // An item of a newer protocol this client does not know.
    _ => null,
  };

  /// Makes the session's feeds carry only [states] and [facts] (null: all
  /// of them, as before the first subscription). A feed open now gets the
  /// values of the states it carries now and did not ([RemoteValues]).
  /// Answers the subscription's number, which that item and the snapshots
  /// after carry.
  Future<int> subscribe({
    Iterable<String>? states,
    Iterable<String>? facts,
    RpcContext? context,
  }) async =>
      (await _caller.subscribe(
            WireSubscribe(states: states?.toList(), facts: facts?.toList()),
            context: _ctx(context),
          )).json['subscription']
          as int;

  /// Calls [command]. When no answer comes back, the result is
  /// [CallLost] with the call's id: retry with it, and the registry answers
  /// the first result without running it again.
  ///
  /// [parent] is what the call follows from: a call the session serves
  /// ([RemoteCall.id]) or a fact (its id).
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    String? parent,
    RpcContext? context,
  }) async => (await callAt(
    command,
    params,
    id: id,
    parent: parent,
    context: context,
  )).result;

  /// [call], with the seq of the epoch the registry had when it answered
  /// (null when the answer was lost): a mirror that reached it shows what
  /// the call wrote.
  Future<({CallResult<Object?> result, String? epoch, int? seq})> callAt(
    String command,
    Map<String, Object?> params, {
    String? id,
    String? parent,
    Principal? as,
    RpcContext? context,
  }) async {
    final callId = id ?? newId();
    try {
      final reply = await _caller.invoke(
        WireCallRequest(
          id: callId,
          command: command,
          params: params,
          parent: parent,
          as: as?.toJson(),
        ),
        context: context,
      );
      return (
        result: CallResult.fromJson(reply.result),
        epoch: reply.epoch,
        seq: reply.seq,
      );
    } on Object catch (e) {
      // Its caller stopped waiting: the call goes on unless the host is
      // told ([cancel]), and a retry with the id answers how it ended.
      if (context?.isCancelled ?? false) {
        return (result: const CallCancelled(), epoch: null, seq: null);
      }
      if (e is RpcStatusException && answeredBySession(e.statusCode)) {
        // The session answered, and not with a result: it refused what was
        // asked of it (a part that is not its own), or failed itself.
        return (
          result: e.statusCode == RpcStatus.permissionDenied
              ? CallRefused(Refusal.notPermitted, e.message)
              : CallFailed('${e.statusCode.name}: ${e.message}'),
          epoch: null,
          seq: null,
        );
      }
      return (result: CallLost(callId, '$e'), epoch: null, seq: null);
    }
  }

  /// Cancels the session's call [id] still running (feature `cancel`): it
  /// answers `cancelled`, and does not run if its handler had not begun.
  Future<void> cancel(String id, {RpcContext? context}) =>
      _caller.cancelCall(WireName(id), context: _ctx(context));

  /// The last [count] facts of [fact] the registry keeps, oldest first.
  Future<List<FactMessage>> recent(
    String fact,
    int count, {
    RpcContext? context,
  }) async => [
    for (final f
        in (await _caller.recent(
              WireRecentRequest(fact, count),
              context: _ctx(context),
            )).json['facts']
            as List)
      FactMessage.fromJson(f),
  ];

  /// Inspects a call's runtime state and recorded decisions.
  Future<Map<String, Object?>> inspectCall(String id) async {
    await _requireCausalDiagnostics(null);
    return (await _caller.why(
      WireWhyRequest(call: id),
      context: _ctx(null),
    )).json;
  }

  /// Why [state] (of [key]) is as it is (Registry.explain).
  Future<Explanation> explain(
    String state, {
    String? key,
    int historyCount = 0,
    RpcContext? context,
  }) async {
    await _requireCausalDiagnostics(context);
    return Explanation.fromJson(
      (await _caller.why(
        WireWhyRequest(state: state, key: key, historyCount: historyCount),
        context: _ctx(context),
      )).json,
    );
  }

  /// Defines [d] as the session's own, as far as the host lets it. A
  /// command's calls come to the session's [RemoteOwner].
  Future<void> define(Descriptor d, {RpcContext? context}) =>
      _caller.define(WireDefine(d.toJson()), context: _ctx(context));

  Future<void> undefine(String name, {RpcContext? context}) =>
      _caller.undefine(WireName(name), context: _ctx(context));

  /// Writes [value] to the session's own [state] (of [key]), or [remove]s
  /// it.
  Future<void> write(
    String state, {
    String? key,
    Object? value,
    bool remove = false,
    String? parent,
    RpcContext? context,
  }) => _caller.write(
    WireSet(
      state: state,
      key: key,
      value: value,
      remove: remove,
      parent: parent,
    ),
    context: _ctx(context),
  );

  /// Applies [ops] in their order as one tick (SPEC §22.4); an answer per
  /// op: `{}`, `{taken}` for a fact said, or `{error, message}`.
  Future<List<Map<String, Object?>>> apply(
    List<Map<String, Object?>> ops, {
    RpcContext? context,
  }) async {
    final r = await _caller.apply(
      WireJson({'ops': ops}),
      context: _ctx(context),
    );
    return [
      for (final x in r.json['results'] as List? ?? const [])
        (x as Map).cast<String, Object?>(),
    ];
  }

  /// Says [fact]: the session's own, or an open one it produces; [by] when
  /// the host lets it say it for someone else. False when [id] was said
  /// already.
  Future<bool> say(
    String fact,
    Object? payload, {
    String? id,
    Principal? by,
    String? parent,
    RpcContext? context,
  }) async => (await _caller.emit(
    WireEmit(
      fact: fact,
      payload: payload,
      id: id,
      by: by?.toJson(),
      parent: parent,
    ),
    context: _ctx(context),
  )).taken;
}
