import 'package:rpc_dart/rpc_dart.dart';

part 'contract.g.dart';

/// The remote protocol's major (SPEC §14): what both ends must share to
/// speak at all. It does not change: the protocol grows by
/// [parlanceFeatures] instead.
const parlanceProtocol = 1;

/// What this end speaks beyond the protocol's first form (SPEC §14), by
/// name. A host tells its own in `describe`; a participant uses one only
/// when the host told it, and refuses to join only when one it requires is
/// not there. A name keeps its meaning for good: a change is a new name
/// beside it, and a name goes when nothing needs it.
const parlanceFeatures = {
  // What a part was built against, by fingerprint (SPEC §6.9, §25.4):
  // the ops `built` and `unbuilt`.
  'built',
  // A feed whose client speaks it tells the entities of a kind that
  // changed as a `kind` item, not the whole catalog again.
  'kinds',
  // A session `main` ends, the connection still up, tells the part across
  // why by an `ended` item, the last of its feeds: it does not join again.
  'ended',
  // A call's caller may cancel it (`cancelled`), and a host tells the
  // participant serving a call that it expired (`expire`).
  'cancel',
};

Map<String, Object?> _obj(Object? v) =>
    (v as Map? ?? const {}).cast<String, Object?>();

/// What `describe` answers: the catalog, the epoch, the seq, the protocol.
final class WireDescription implements IRpcSerializable {
  const WireDescription(this.json);

  factory WireDescription.fromJson(Map<String, dynamic> m) =>
      WireDescription(m);

  final Map<String, Object?> json;

  @override
  Map<String, dynamic> toJson() => json;
}

/// Asks for the feed, resuming after [since] of [epoch] when given.
final class WireFeedRequest implements IRpcSerializable {
  const WireFeedRequest({this.epoch, this.since, this.features});

  factory WireFeedRequest.fromJson(Map<String, dynamic> m) => WireFeedRequest(
    epoch: m['epoch'] as String?,
    since: m['since'] as int?,
    features: switch (m['features']) {
      final List<Object?> l => {for (final f in l) '$f'},
      _ => null,
    },
  );

  final String? epoch;
  final int? since;

  /// The features the client speaks (SPEC §14), for the host to send it
  /// what they make: a client of before them says none.
  final Set<String>? features;

  @override
  Map<String, dynamic> toJson() => {
    'epoch': ?epoch,
    'since': ?since,
    if (features case final f?) 'features': [...f],
  };
}

/// What a session's feeds carry: these states and facts, or all of them
/// (null).
final class WireSubscribe implements IRpcSerializable {
  const WireSubscribe({this.states, this.facts});

  factory WireSubscribe.fromJson(Map<String, dynamic> m) => WireSubscribe(
    states: (m['states'] as List?)?.cast<String>(),
    facts: (m['facts'] as List?)?.cast<String>(),
  );

  final List<String>? states;
  final List<String>? facts;

  @override
  Map<String, dynamic> toJson() => {'states': ?states, 'facts': ?facts};
}

/// One item of the feed: the catalog, a snapshot, a tick, or the values of
/// states a subscription took in.
final class WireFeedItem implements IRpcSerializable {
  const WireFeedItem(this.kind, this.json);

  factory WireFeedItem.fromJson(Map<String, dynamic> m) =>
      WireFeedItem(m['kind'] as String, _obj(m['item']));

  /// `catalog`, `snapshot`, `tick` or `values`.
  final String kind;
  final Map<String, Object?> json;

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'item': json};
}

/// A call. Its [id] makes a retry safe: the same id answers the first
/// result without running again.
final class WireCallRequest implements IRpcSerializable {
  const WireCallRequest({
    required this.id,
    required this.command,
    this.params = const {},
    this.parent,
    this.as,
  });

  factory WireCallRequest.fromJson(Map<String, dynamic> m) => WireCallRequest(
    id: m['id'] as String,
    command: m['command'] as String,
    params: _obj(m['params']),
    parent: m['parent'] as String?,
    as: m['as'] == null ? null : _obj(m['as']),
  );

  final String id;
  final String command;
  final Map<String, Object?> params;

  /// What it follows from: a call the session serves, or a fact.
  final String? parent;

  /// The owner of the session's principal that calls (SPEC §22.3), as
  /// `Principal.toJson` gives it; null for the session's principal.
  final Map<String, Object?>? as;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'params': params,
    'parent': ?parent,
    'as': ?as,
  };
}

/// How a call ended, as `CallResult.toJson` gives it, and the seq of
/// [epoch] the registry had then: a feed that reached it shows what the
/// call wrote.
final class WireCallReply implements IRpcSerializable {
  const WireCallReply(this.result, {required this.epoch, required this.seq});

  factory WireCallReply.fromJson(Map<String, dynamic> m) => WireCallReply(
    _obj(m['result']),
    epoch: m['epoch'] as String,
    seq: m['seq'] as int,
  );

  final Map<String, Object?> result;
  final String epoch;
  final int seq;

  @override
  Map<String, dynamic> toJson() => {
    'result': result,
    'epoch': epoch,
    'seq': seq,
  };
}

/// Asks for the last [count] facts of [fact].
final class WireRecentRequest implements IRpcSerializable {
  const WireRecentRequest(this.fact, this.count);

  factory WireRecentRequest.fromJson(Map<String, dynamic> m) =>
      WireRecentRequest(m['fact'] as String, m['count'] as int);

  final String fact;
  final int count;

  @override
  Map<String, dynamic> toJson() => {'fact': fact, 'count': count};
}

/// Any JSON object: what `why` and `recent` answer.
final class WireJson implements IRpcSerializable {
  const WireJson(this.json);

  factory WireJson.fromJson(Map<String, dynamic> m) => WireJson(m);

  final Map<String, Object?> json;

  @override
  Map<String, dynamic> toJson() => json;
}

/// Asks why a state (of a key) is as it is.
final class WireWhyRequest implements IRpcSerializable {
  const WireWhyRequest(this.state, {this.key});

  factory WireWhyRequest.fromJson(Map<String, dynamic> m) =>
      WireWhyRequest(m['state'] as String, key: m['key'] as String?);

  final String state;
  final String? key;

  @override
  Map<String, dynamic> toJson() => {'state': state, 'key': ?key};
}

/// A word to define for the session, as `Descriptor.toJson` gives it.
final class WireDefine implements IRpcSerializable {
  const WireDefine(this.descriptor);

  factory WireDefine.fromJson(Map<String, dynamic> m) =>
      WireDefine(_obj(m['descriptor']));

  final Map<String, Object?> descriptor;

  @override
  Map<String, dynamic> toJson() => {'descriptor': descriptor};
}

/// A word by name.
final class WireName implements IRpcSerializable {
  const WireName(this.name);

  factory WireName.fromJson(Map<String, dynamic> m) =>
      WireName(m['name'] as String);

  final String name;

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

/// Writes a state the session owns: [value] (of [key]), or removes it.
final class WireSet implements IRpcSerializable {
  const WireSet({
    required this.state,
    this.key,
    this.value,
    this.remove = false,
    this.parent,
  });

  factory WireSet.fromJson(Map<String, dynamic> m) => WireSet(
    state: m['state'] as String,
    key: m['key'] as String?,
    value: m['value'],
    remove: m['remove'] == true,
    parent: m['parent'] as String?,
  );

  final String state;
  final String? key;
  final Object? value;
  final bool remove;

  /// What it follows from: a call the session serves, or a fact.
  final String? parent;

  @override
  Map<String, dynamic> toJson() => {
    'state': state,
    'key': ?key,
    'value': value,
    if (remove) 'remove': true,
    'parent': ?parent,
  };
}

/// Says a fact: one the session owns, or an open one it produces; [by] when
/// the host lets it say it for someone else.
final class WireEmit implements IRpcSerializable {
  const WireEmit({
    required this.fact,
    this.payload,
    this.id,
    this.by,
    this.parent,
  });

  factory WireEmit.fromJson(Map<String, dynamic> m) => WireEmit(
    fact: m['fact'] as String,
    payload: m['payload'],
    id: m['id'] as String?,
    by: m['by'] == null ? null : _obj(m['by']),
    parent: m['parent'] as String?,
  );

  final String fact;
  final Object? payload;

  /// Its own id, for a repeat to be dropped.
  final String? id;

  /// On whose behalf, as `Principal.toJson` gives it.
  final Map<String, Object?>? by;
  final String? parent;

  @override
  Map<String, dynamic> toJson() => {
    'fact': fact,
    'payload': payload,
    'id': ?id,
    'by': ?by,
    'parent': ?parent,
  };
}

/// Whether a fact was taken: false for a repeat of its id.
final class WireTaken implements IRpcSerializable {
  const WireTaken(this.taken);

  factory WireTaken.fromJson(Map<String, dynamic> m) =>
      WireTaken(m['taken'] == true);

  final bool taken;

  @override
  Map<String, dynamic> toJson() => {'taken': taken};
}

/// A call of a command the session owns, for it to serve.
final class WireServe implements IRpcSerializable {
  const WireServe({
    required this.id,
    required this.command,
    required this.params,
    required this.cause,
    this.traceparent,
  });

  factory WireServe.fromJson(Map<String, dynamic> m) => WireServe(
    id: m['id'] as String,
    command: m['command'] as String,
    params: _obj(m['params']),
    cause: _obj(m['cause']),
    traceparent: m['traceparent'] as String?,
  );

  final String id;
  final String command;

  /// Checked, with defaults filled.
  final Map<String, Object?> params;

  /// As `Cause.toJson` gives it.
  final Map<String, Object?> cause;

  /// The call's span on the host as a W3C `traceparent` (SPEC §9.2): the
  /// participant serves it in a child span, in the host's trace.
  final String? traceparent;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'params': params,
    'cause': cause,
    'traceparent': ?traceparent,
  };
}

/// How the session served a call: [value], or why it failed.
final class WireServed implements IRpcSerializable {
  const WireServed.done(this.value) : error = null;
  const WireServed.failed(String this.error) : value = null;

  factory WireServed.fromJson(Map<String, dynamic> m) => m['error'] is String
      ? WireServed.failed(m['error'] as String)
      : WireServed.done(m['value']);

  final Object? value;
  final String? error;

  @override
  Map<String, dynamic> toJson() =>
      error == null ? {'value': value} : {'error': error};
}

/// The registry over rpc_dart (SPEC §14), its side of a peer connection.
/// One per session: the host makes it for a connection, with the principal
/// it accepted.
@RpcService(name: 'Parlance', kind: RpcServiceKind.peer)
abstract class IParlanceContract {
  @RpcMethod.unary(name: 'describe')
  Future<WireDescription> describe(RpcNull request, {RpcContext? context});

  @RpcMethod.serverStream(name: 'feed')
  Stream<WireFeedItem> feed(WireFeedRequest request, {RpcContext? context});

  @RpcMethod.unary(name: 'call')
  Future<WireCallReply> invoke(WireCallRequest request, {RpcContext? context});

  @RpcMethod.unary(name: 'why')
  Future<WireJson> why(WireWhyRequest request, {RpcContext? context});

  @RpcMethod.unary(name: 'recent')
  Future<WireJson> recent(WireRecentRequest request, {RpcContext? context});

  /// Answers `{subscription}`: the number the feeds' `values` item (or
  /// the next snapshot) carries once they follow it.
  @RpcMethod.unary(name: 'subscribe')
  Future<WireJson> subscribe(WireSubscribe request, {RpcContext? context});

  @RpcMethod.unary(name: 'define')
  Future<RpcNull> define(WireDefine request, {RpcContext? context});

  @RpcMethod.unary(name: 'undefine')
  Future<RpcNull> undefine(WireName request, {RpcContext? context});

  @RpcMethod.unary(name: 'set')
  Future<RpcNull> write(WireSet request, {RpcContext? context});

  @RpcMethod.unary(name: 'emit')
  Future<WireTaken> emit(WireEmit request, {RpcContext? context});

  /// What a remote participant asked, in its order, applied as one tick
  /// (SPEC §22.4): `{ops: [...]}`, answered `{results: [...]}`, one each.
  @RpcMethod.unary(name: 'apply')
  Future<WireJson> apply(WireJson request, {RpcContext? context});
}

/// The participant's side of the connection (SPEC §14): it serves the calls
/// of the commands its session owns.
@RpcService(name: 'ParlanceOwner', kind: RpcServiceKind.peer)
abstract class IParlanceOwnerContract {
  @RpcMethod.unary(name: 'serve')
  Future<WireServed> serve(WireServe request, {RpcContext? context});

  /// Asks a guard of the participant's own about a call of its command
  /// (SPEC §22.4): `{guard, id, command, params, cause}`, answered
  /// `{why}`, null to let it pass.
  @RpcMethod.unary(name: 'judge')
  Future<WireJson> judge(WireJson request, {RpcContext? context});

  /// Tells the participant a call it serves expired (feature `cancel`):
  /// its caller cancelled it, or its deadline passed. The handler is told
  /// (`expired`); its answer still comes, and is recorded late.
  @RpcMethod.unary(name: 'expire')
  Future<RpcNull> expire(WireName request, {RpcContext? context});
}
