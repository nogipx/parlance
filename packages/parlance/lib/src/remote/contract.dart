import 'package:rpc_dart/rpc_dart.dart';

part 'contract.g.dart';

/// The version of the remote protocol (SPEC §14).
const parlanceProtocol = 5;

Map<String, Object?> _obj(Object? v) =>
    (v as Map? ?? const {}).cast<String, Object?>();

/// What `describe` answers: the catalog, the epoch, the seq, the protocol.
final class SbDescription implements IRpcSerializable {
  const SbDescription(this.json);

  factory SbDescription.fromJson(Map<String, dynamic> m) => SbDescription(m);

  final Map<String, Object?> json;

  @override
  Map<String, dynamic> toJson() => json;
}

/// Asks for the feed, resuming after [since] of [epoch] when given.
final class SbFeedRequest implements IRpcSerializable {
  const SbFeedRequest({this.epoch, this.since});

  factory SbFeedRequest.fromJson(Map<String, dynamic> m) =>
      SbFeedRequest(epoch: m['epoch'] as String?, since: m['since'] as int?);

  final String? epoch;
  final int? since;

  @override
  Map<String, dynamic> toJson() => {'epoch': ?epoch, 'since': ?since};
}

/// What a session's feeds carry: these states and facts, or all of them
/// (null).
final class SbSubscribe implements IRpcSerializable {
  const SbSubscribe({this.states, this.facts});

  factory SbSubscribe.fromJson(Map<String, dynamic> m) => SbSubscribe(
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
final class SbFeedItem implements IRpcSerializable {
  const SbFeedItem(this.kind, this.json);

  factory SbFeedItem.fromJson(Map<String, dynamic> m) =>
      SbFeedItem(m['kind'] as String, _obj(m['item']));

  /// `catalog`, `snapshot`, `tick` or `values`.
  final String kind;
  final Map<String, Object?> json;

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'item': json};
}

/// A call. Its [id] makes a retry safe: the same id answers the first
/// result without running again.
final class SbCallRequest implements IRpcSerializable {
  const SbCallRequest({
    required this.id,
    required this.command,
    this.params = const {},
    this.overriding = false,
    this.test = false,
    this.parent,
  });

  factory SbCallRequest.fromJson(Map<String, dynamic> m) => SbCallRequest(
    id: m['id'] as String,
    command: m['command'] as String,
    params: _obj(m['params']),
    overriding: m['override'] == true,
    test: m['test'] == true,
    parent: m['parent'] as String?,
  );

  final String id;
  final String command;
  final Map<String, Object?> params;

  /// Override overridable denials (SPEC §9); named so it does not hide the
  /// `@override` annotation.
  final bool overriding;
  final bool test;

  /// What it follows from: a call the session serves, or a fact.
  final String? parent;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'params': params,
    if (overriding) 'override': true,
    if (test) 'test': true,
    'parent': ?parent,
  };
}

/// How a call ended, as `CallResult.toJson` gives it, and the seq of
/// [epoch] the registry had then: a feed that reached it shows what the
/// call wrote.
final class SbCallReply implements IRpcSerializable {
  const SbCallReply(this.result, {required this.epoch, required this.seq});

  factory SbCallReply.fromJson(Map<String, dynamic> m) => SbCallReply(
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
final class SbRecentRequest implements IRpcSerializable {
  const SbRecentRequest(this.fact, this.count);

  factory SbRecentRequest.fromJson(Map<String, dynamic> m) =>
      SbRecentRequest(m['fact'] as String, m['count'] as int);

  final String fact;
  final int count;

  @override
  Map<String, dynamic> toJson() => {'fact': fact, 'count': count};
}

/// Holds a state at a value for the session (SPEC §8, §14).
final class SbLayerRequest implements IRpcSerializable {
  const SbLayerRequest({
    required this.state,
    this.key,
    required this.value,
    this.priority = 0,
    this.ttlMs,
  });

  factory SbLayerRequest.fromJson(Map<String, dynamic> m) => SbLayerRequest(
    state: m['state'] as String,
    key: m['key'] as String?,
    value: m['value'],
    priority: m['priority'] as int? ?? 0,
    ttlMs: m['ttlMs'] as int?,
  );

  final String state;
  final String? key;
  final Object? value;
  final int priority;
  final int? ttlMs;

  @override
  Map<String, dynamic> toJson() => {
    'state': state,
    'key': ?key,
    'value': value,
    if (priority != 0) 'priority': priority,
    'ttlMs': ?ttlMs,
  };
}

/// A layer of the session, by id.
final class SbLayerRef implements IRpcSerializable {
  const SbLayerRef(this.layer);

  factory SbLayerRef.fromJson(Map<String, dynamic> m) =>
      SbLayerRef(m['layer'] as String);

  final String layer;

  @override
  Map<String, dynamic> toJson() => {'layer': layer};
}

/// What happened to a layer of the session, as `LayerEvent.toJson` gives it.
final class SbLayerEvent implements IRpcSerializable {
  const SbLayerEvent(this.json);

  factory SbLayerEvent.fromJson(Map<String, dynamic> m) => SbLayerEvent(m);

  final Map<String, Object?> json;

  @override
  Map<String, dynamic> toJson() => json;
}

/// Any JSON object: what `why`, `layers` and `recent` answer.
final class SbJson implements IRpcSerializable {
  const SbJson(this.json);

  factory SbJson.fromJson(Map<String, dynamic> m) => SbJson(m);

  final Map<String, Object?> json;

  @override
  Map<String, dynamic> toJson() => json;
}

/// Asks why a state (of a key) is as it is.
final class SbWhyRequest implements IRpcSerializable {
  const SbWhyRequest(this.state, {this.key});

  factory SbWhyRequest.fromJson(Map<String, dynamic> m) =>
      SbWhyRequest(m['state'] as String, key: m['key'] as String?);

  final String state;
  final String? key;

  @override
  Map<String, dynamic> toJson() => {'state': state, 'key': ?key};
}

/// A word to define for the session, as `Descriptor.toJson` gives it.
final class SbDefine implements IRpcSerializable {
  const SbDefine(this.descriptor);

  factory SbDefine.fromJson(Map<String, dynamic> m) =>
      SbDefine(_obj(m['descriptor']));

  final Map<String, Object?> descriptor;

  @override
  Map<String, dynamic> toJson() => {'descriptor': descriptor};
}

/// A word by name.
final class SbName implements IRpcSerializable {
  const SbName(this.name);

  factory SbName.fromJson(Map<String, dynamic> m) =>
      SbName(m['name'] as String);

  final String name;

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

/// Writes a state the session owns: [value] (of [key]), or removes it.
final class SbSet implements IRpcSerializable {
  const SbSet({
    required this.state,
    this.key,
    this.value,
    this.remove = false,
    this.parent,
    this.test = false,
  });

  factory SbSet.fromJson(Map<String, dynamic> m) => SbSet(
    state: m['state'] as String,
    key: m['key'] as String?,
    value: m['value'],
    remove: m['remove'] == true,
    parent: m['parent'] as String?,
    test: m['test'] == true,
  );

  final String state;
  final String? key;
  final Object? value;
  final bool remove;

  /// What it follows from: a call the session serves, or a fact.
  final String? parent;
  final bool test;

  @override
  Map<String, dynamic> toJson() => {
    'state': state,
    'key': ?key,
    'value': value,
    if (remove) 'remove': true,
    'parent': ?parent,
    if (test) 'test': true,
  };
}

/// Says a fact: one the session owns, or an open one it produces; [by] when
/// the host lets it say it for someone else.
final class SbEmit implements IRpcSerializable {
  const SbEmit({
    required this.fact,
    this.payload,
    this.id,
    this.by,
    this.parent,
    this.test = false,
  });

  factory SbEmit.fromJson(Map<String, dynamic> m) => SbEmit(
    fact: m['fact'] as String,
    payload: m['payload'],
    id: m['id'] as String?,
    by: m['by'] == null ? null : _obj(m['by']),
    parent: m['parent'] as String?,
    test: m['test'] == true,
  );

  final String fact;
  final Object? payload;

  /// Its own id, for a repeat to be dropped.
  final String? id;

  /// On whose behalf, as `Principal.toJson` gives it.
  final Map<String, Object?>? by;
  final String? parent;
  final bool test;

  @override
  Map<String, dynamic> toJson() => {
    'fact': fact,
    'payload': payload,
    'id': ?id,
    'by': ?by,
    'parent': ?parent,
    if (test) 'test': true,
  };
}

/// Whether a fact was taken: false for a repeat of its id.
final class SbTaken implements IRpcSerializable {
  const SbTaken(this.taken);

  factory SbTaken.fromJson(Map<String, dynamic> m) =>
      SbTaken(m['taken'] == true);

  final bool taken;

  @override
  Map<String, dynamic> toJson() => {'taken': taken};
}

/// A call of a command the session owns, for it to serve.
final class SbServe implements IRpcSerializable {
  const SbServe({
    required this.id,
    required this.command,
    required this.params,
    required this.cause,
  });

  factory SbServe.fromJson(Map<String, dynamic> m) => SbServe(
    id: m['id'] as String,
    command: m['command'] as String,
    params: _obj(m['params']),
    cause: _obj(m['cause']),
  );

  final String id;
  final String command;

  /// Checked, with defaults filled.
  final Map<String, Object?> params;

  /// As `Cause.toJson` gives it.
  final Map<String, Object?> cause;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'params': params,
    'cause': cause,
  };
}

/// How the session served a call: [value], or why it failed.
final class SbServed implements IRpcSerializable {
  const SbServed.done(this.value) : error = null;
  const SbServed.failed(String this.error) : value = null;

  factory SbServed.fromJson(Map<String, dynamic> m) => m['error'] is String
      ? SbServed.failed(m['error'] as String)
      : SbServed.done(m['value']);

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
  Future<SbDescription> describe(RpcNull request, {RpcContext? context});

  @RpcMethod.serverStream(name: 'feed')
  Stream<SbFeedItem> feed(SbFeedRequest request, {RpcContext? context});

  @RpcMethod.unary(name: 'call')
  Future<SbCallReply> invoke(SbCallRequest request, {RpcContext? context});

  @RpcMethod.unary(name: 'pushLayer')
  Future<SbLayerRef> pushLayer(SbLayerRequest request, {RpcContext? context});

  @RpcMethod.unary(name: 'popLayer')
  Future<RpcNull> popLayer(SbLayerRef request, {RpcContext? context});

  @RpcMethod.serverStream(name: 'layerEvents')
  Stream<SbLayerEvent> layerEvents(RpcNull request, {RpcContext? context});

  @RpcMethod.unary(name: 'why')
  Future<SbJson> why(SbWhyRequest request, {RpcContext? context});

  @RpcMethod.unary(name: 'layers')
  Future<SbJson> layers(RpcNull request, {RpcContext? context});

  @RpcMethod.unary(name: 'recent')
  Future<SbJson> recent(SbRecentRequest request, {RpcContext? context});

  /// Answers `{subscription}`: the number the feeds' `values` item (or
  /// the next snapshot) carries once they follow it.
  @RpcMethod.unary(name: 'subscribe')
  Future<SbJson> subscribe(SbSubscribe request, {RpcContext? context});

  @RpcMethod.unary(name: 'define')
  Future<RpcNull> define(SbDefine request, {RpcContext? context});

  @RpcMethod.unary(name: 'undefine')
  Future<RpcNull> undefine(SbName request, {RpcContext? context});

  @RpcMethod.unary(name: 'set')
  Future<RpcNull> write(SbSet request, {RpcContext? context});

  @RpcMethod.unary(name: 'emit')
  Future<SbTaken> emit(SbEmit request, {RpcContext? context});
}

/// The participant's side of the connection (SPEC §14): it serves the calls
/// of the commands its session owns.
@RpcService(name: 'ParlanceOwner', kind: RpcServiceKind.peer)
abstract class IParlanceOwnerContract {
  @RpcMethod.unary(name: 'serve')
  Future<SbServed> serve(SbServe request, {RpcContext? context});
}
