import 'package:rpc_dart/rpc_dart.dart';

part 'contract.g.dart';

/// The version of the remote protocol (SPEC §14).
const switchboardProtocol = 1;

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

/// One item of the feed: the catalog, a snapshot or a tick.
final class SbFeedItem implements IRpcSerializable {
  const SbFeedItem(this.kind, this.json);

  factory SbFeedItem.fromJson(Map<String, dynamic> m) =>
      SbFeedItem(m['kind'] as String, _obj(m['item']));

  /// `catalog`, `snapshot` or `tick`.
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
  });

  factory SbCallRequest.fromJson(Map<String, dynamic> m) => SbCallRequest(
    id: m['id'] as String,
    command: m['command'] as String,
    params: _obj(m['params']),
    overriding: m['override'] == true,
    test: m['test'] == true,
  );

  final String id;
  final String command;
  final Map<String, Object?> params;

  /// Override overridable denials (SPEC §9); named so it does not hide the
  /// `@override` annotation.
  final bool overriding;
  final bool test;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'params': params,
    if (overriding) 'override': true,
    if (test) 'test': true,
  };
}

/// How a call ended, as `CallResult.toJson` gives it.
final class SbCallReply implements IRpcSerializable {
  const SbCallReply(this.json);

  factory SbCallReply.fromJson(Map<String, dynamic> m) => SbCallReply(m);

  final Map<String, Object?> json;

  @override
  Map<String, dynamic> toJson() => json;
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

/// Any JSON object: what `why` and `layers` answer.
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

/// The registry over rpc_dart (SPEC §14). One responder per session: the
/// host makes it for a connection, with the principal it accepted.
@RpcService(name: 'Switchboard')
abstract class ISwitchboardContract {
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
}
