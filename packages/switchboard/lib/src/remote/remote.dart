import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';

import '../registry/cause.dart';
import '../registry/ids.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/types.dart';
import 'contract.dart';

// --- The registry's side -------------------------------------------------------

/// One session of a remote participant (SPEC §14): the registry as the
/// principal the host accepted for this connection may see and use it.
///
/// Register it on the connection's responder endpoint; [close] it when the
/// connection ends, so the layers the session holds go.
final class RegistryResponder extends SwitchboardContractResponder {
  RegistryResponder(this.registry, {required this.principal, String? session})
    : session = session ?? newId();

  final Registry registry;

  /// Who the session acts for; fixed when the host accepted the connection.
  final Principal principal;
  final String session;

  /// The owner of the layers the session pushes.
  String get owner => 'remote:$session';

  final Map<String, LayerHandle> _layers = {};
  bool _closed = false;

  void _open() {
    if (_closed) {
      throw RpcStatusException(RpcStatus.unavailable, 'the session ended');
    }
  }

  @override
  Future<SbDescription> describe(RpcNull request, {RpcContext? context}) async {
    _open();
    // What this session may call: so its clients offer only that.
    return SbDescription({
      ...registry.describeFor(principal),
      'protocol': switchboardProtocol,
    });
  }

  @override
  Future<SbJson> why(SbWhyRequest request, {RpcContext? context}) async {
    _open();
    if (registry.stateDescriptor(request.state) == null) {
      throw RpcStatusException(RpcStatus.notFound, 'no state ${request.state}');
    }
    return SbJson(registry.explain(request.state, key: request.key).toJson());
  }

  @override
  Future<SbJson> layers(RpcNull request, {RpcContext? context}) async {
    _open();
    return SbJson({
      'layers': [for (final l in registry.layers()) l.toJson()],
    });
  }

  @override
  Stream<SbFeedItem> feed(SbFeedRequest request, {RpcContext? context}) {
    _open();
    late StreamController<SbFeedItem> out;
    StreamSubscription<FeedItem>? items;
    StreamSubscription<CatalogChange>? catalog;
    out = StreamController<SbFeedItem>(
      onListen: () {
        out.add(SbFeedItem('catalog', registry.describe()));
        catalog = registry.catalogChanges.listen(
          (_) => out.add(SbFeedItem('catalog', registry.describe())),
        );
        items = registry
            .feed(epoch: request.epoch, since: request.since)
            .listen(
              (i) => out.add(switch (i) {
                Snapshot() => SbFeedItem('snapshot', i.toJson()),
                Tick() => SbFeedItem('tick', i.toJson()),
              }),
            );
      },
      onCancel: () async {
        await items?.cancel();
        await catalog?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<SbCallReply> invoke(
    SbCallRequest request, {
    RpcContext? context,
  }) async {
    _open();
    // Ids are the principal's own: another principal reusing one does not
    // get this one's answer.
    final result = await registry.call(
      request.command,
      request.params,
      by: principal,
      id: '${principal.selector}/${request.id}',
      override: request.overriding,
      cause: Cause(principal, test: request.test),
    );
    return SbCallReply(
      result.toJson(),
      epoch: registry.epoch,
      seq: registry.seq,
    );
  }

  @override
  Future<SbJson> recent(SbRecentRequest request, {RpcContext? context}) async {
    _open();
    if (registry.factDescriptor(request.fact) == null) {
      throw RpcStatusException(RpcStatus.notFound, 'no fact ${request.fact}');
    }
    return SbJson({
      'facts': [
        for (final f in registry.recent(request.fact, request.count))
          f.toJson(),
      ],
    });
  }

  @override
  Future<SbLayerRef> pushLayer(
    SbLayerRequest request, {
    RpcContext? context,
  }) async {
    _open();
    if (registry.stateDescriptor(request.state) == null) {
      throw RpcStatusException(RpcStatus.notFound, 'no state ${request.state}');
    }
    final setter = registry.setterOf(request.state);
    if (setter == null) {
      throw RpcStatusException(
        RpcStatus.failedPrecondition,
        '${request.state} has no setter',
      );
    }
    if (registry.commandDescriptor(setter)?.callers.allows(principal) != true) {
      throw RpcStatusException(
        RpcStatus.permissionDenied,
        '$principal may not set ${request.state}',
      );
    }
    try {
      final h = registry.pushLayer(
        request.state,
        key: request.key,
        value: request.value,
        owner: owner,
        by: principal,
        priority: request.priority,
        ttl: request.ttlMs == null
            ? null
            : Duration(milliseconds: request.ttlMs!),
        chain: [owner],
      );
      _layers[h.id] = h;
      return SbLayerRef(h.id);
    } on TypeMismatch catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '$e');
    } on ArgumentError catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '${e.message}');
    }
  }

  @override
  Future<RpcNull> popLayer(SbLayerRef request, {RpcContext? context}) async {
    _open();
    final h = _layers.remove(request.layer);
    if (h == null) {
      throw RpcStatusException(RpcStatus.notFound, 'no layer ${request.layer}');
    }
    h.dispose();
    return const RpcNull();
  }

  @override
  Stream<SbLayerEvent> layerEvents(RpcNull request, {RpcContext? context}) {
    _open();
    return registry.layerEvents
        .where((e) => e.owner == owner)
        .map((e) => SbLayerEvent(e.toJson()));
  }

  /// Ends the session: its layers go, its calls are refused.
  void close() {
    if (_closed) return;
    _closed = true;
    _layers.clear();
    registry.dropLayersOf(owner);
  }
}

// --- The participant's side ----------------------------------------------------

/// What a remote feed gives (SPEC §12, §14).
sealed class RemoteFeed {
  const RemoteFeed();
}

/// The catalog, as `describe` gives it; first, and on every change.
final class RemoteCatalog extends RemoteFeed {
  const RemoteCatalog(this.json);
  final Map<String, Object?> json;
}

final class RemoteSnapshot extends RemoteFeed {
  const RemoteSnapshot(this.snapshot);
  final Snapshot snapshot;
}

final class RemoteTick extends RemoteFeed {
  const RemoteTick(this.tick);
  final Tick tick;
}

/// The registry as a remote participant uses it, over a caller endpoint.
final class SwitchboardClient {
  SwitchboardClient(
    RpcCallerEndpoint endpoint, {
    this.timeout = const Duration(seconds: 10),
  }) : _caller = SwitchboardContractCaller(endpoint);

  final SwitchboardContractCaller _caller;

  /// The deadline of a request the registry answers at once (describe,
  /// why, layers, pushing and popping one), without a context of its own.
  /// A [call] has none: the registry bounds it itself, its hooks and its
  /// handler, and answers a timeout.
  final Duration timeout;

  RpcContext _ctx(RpcContext? c) =>
      c ?? RpcContext.empty().withTimeout(timeout);

  Future<Map<String, Object?>> describe({RpcContext? context}) async =>
      (await _caller.describe(const RpcNull(), context: _ctx(context))).json;

  /// The feed: the catalog, then a snapshot or the ticks after [since] of
  /// [epoch], then live. Cancel the subscription to end it.
  Stream<RemoteFeed> feed({String? epoch, int? since, RpcContext? context}) =>
      _caller
          .feed(
            SbFeedRequest(epoch: epoch, since: since),
            context: context,
          )
          .map(
            (i) => switch (i.kind) {
              'catalog' => RemoteCatalog(i.json),
              'snapshot' => RemoteSnapshot(Snapshot.fromJson(i.json)),
              _ => RemoteTick(Tick.fromJson(i.json)),
            },
          );

  /// Calls [command]. When no answer comes back, the result is
  /// [CallLost] with the call's id: retry with it, and the registry answers
  /// the first result without running it again.
  Future<CallResult> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    bool override = false,
    bool test = false,
    RpcContext? context,
  }) async => (await callAt(
    command,
    params,
    id: id,
    override: override,
    test: test,
    context: context,
  )).result;

  /// [call], with the seq of the epoch the registry had when it answered
  /// (null when the answer was lost): a mirror that reached it shows what
  /// the call wrote.
  Future<({CallResult result, String? epoch, int? seq})> callAt(
    String command,
    Map<String, Object?> params, {
    String? id,
    bool override = false,
    bool test = false,
    RpcContext? context,
  }) async {
    final callId = id ?? newId();
    try {
      final reply = await _caller.invoke(
        SbCallRequest(
          id: callId,
          command: command,
          params: params,
          overriding: override,
          test: test,
        ),
        context: context,
      );
      return (
        result: CallResult.fromJson(reply.result),
        epoch: reply.epoch,
        seq: reply.seq,
      );
    } on Object catch (e) {
      return (result: CallLost(callId, '$e'), epoch: null, seq: null);
    }
  }

  /// The last [count] facts of [fact] the registry keeps, oldest first.
  Future<List<FactMessage>> recent(
    String fact,
    int count, {
    RpcContext? context,
  }) async => [
    for (final f
        in (await _caller.recent(
              SbRecentRequest(fact, count),
              context: _ctx(context),
            )).json['facts']
            as List)
      FactMessage.fromJson(f),
  ];

  /// Holds [state] (of [key]) at [value] while the session lasts, or for
  /// [ttl]; answers the layer's id.
  Future<String> pushLayer(
    String state, {
    String? key,
    required Object? value,
    int priority = 0,
    Duration? ttl,
    RpcContext? context,
  }) async => (await _caller.pushLayer(
    SbLayerRequest(
      state: state,
      key: key,
      value: value,
      priority: priority,
      ttlMs: ttl?.inMilliseconds,
    ),
    context: _ctx(context),
  )).layer;

  Future<void> popLayer(String layer, {RpcContext? context}) =>
      _caller.popLayer(SbLayerRef(layer), context: _ctx(context));

  /// Why [state] (of [key]) is as it is (Registry.explain).
  Future<Explanation> why(
    String state, {
    String? key,
    RpcContext? context,
  }) async => Explanation.fromJson(
    (await _caller.why(
      SbWhyRequest(state, key: key),
      context: _ctx(context),
    )).json,
  );

  /// Every layer there is.
  Future<List<LayerInfo>> layers({RpcContext? context}) async => [
    for (final l
        in (await _caller.layers(
              const RpcNull(),
              context: _ctx(context),
            )).json['layers']
            as List)
      LayerInfo.fromJson(l),
  ];

  /// What happens to the session's layers.
  Stream<LayerEvent> layerEvents({RpcContext? context}) => _caller
      .layerEvents(const RpcNull(), context: context)
      .map((e) => LayerEvent.fromJson(e.json));
}

/// A remote participant's copy of the registry's states, kept by a feed and
/// resumed after a lost connection without gaps or repeats (SPEC §12).
final class RegistryMirror {
  String? _epoch;
  int _seq = 0;
  Map<String, Object?> _catalog = const {};
  final Map<String, Map<String?, Object?>> _states = {};
  SwitchboardClient? _client;
  StreamSubscription<RemoteFeed>? _sub;
  bool _synced = false;
  final StreamController<Tick> _ticks = StreamController.broadcast();
  final StreamController<void> _changes = StreamController.broadcast();
  final StreamController<void> _catalogChanges = StreamController.broadcast();

  String? get epoch => _epoch;
  int get seq => _seq;

  /// The catalog as `describe` gives it.
  Map<String, Object?> get catalog => _catalog;

  /// Whether the copy follows the registry now.
  bool get synced => _synced;

  /// The ticks applied, in order.
  Stream<Tick> get ticks => _ticks.stream;

  /// Something changed: a snapshot, a tick, the catalog, the connection.
  Stream<void> get changes => _changes.stream;

  /// The catalog came: first after following, and on every change of it
  /// (descriptors or entities).
  Stream<void> get catalogChanges => _catalogChanges.stream;

  Object? read(String state, {String? key}) => _states[state]?[key];

  /// Completes when the copy has the seq [seq] of [epoch] (what a call
  /// answered at it wrote), or after [timeout]; answers whether it got
  /// there.
  Future<bool> reach(
    String epoch,
    int seq, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    bool there() => _synced && _epoch == epoch && _seq >= seq;
    if (there()) return true;
    try {
      await changes.firstWhere((_) => there()).timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } on StateError {
      return false;
    }
  }

  Map<String?, Object?> readAll(String state) =>
      Map.unmodifiable(_states[state] ?? const {});

  /// Follows [client]'s feed, resuming after what the copy already has.
  /// Call again with a new client after the connection was lost.
  void follow(SwitchboardClient client) {
    _client = client;
    unawaited(_sub?.cancel());
    _sub = client
        .feed(epoch: _epoch, since: _epoch == null ? null : _seq)
        .listen(
          _apply,
          onError: (Object _) => _lost(),
          onDone: _lost,
          cancelOnError: true,
        );
  }

  void _lost() {
    _synced = false;
    _changes.add(null);
  }

  void _apply(RemoteFeed item) {
    switch (item) {
      case RemoteCatalog(:final json):
        _catalog = json;
        _catalogChanges.add(null);
      case RemoteSnapshot(:final snapshot):
        _epoch = snapshot.epoch;
        _seq = snapshot.seq;
        _states
          ..clear()
          ..addAll({
            for (final e in snapshot.states.entries) e.key: {...e.value},
          });
        _synced = true;
      case RemoteTick(:final tick):
        if (tick.epoch != _epoch || tick.from != _seq + 1) {
          // A gap: start over from a snapshot.
          _epoch = null;
          if (_client case final c?) follow(c);
          return;
        }
        for (final c in tick.changes) {
          if (c.removed) {
            _states[c.state]?.remove(c.key);
          } else {
            (_states[c.state] ??= {})[c.key] = c.value;
          }
        }
        _seq = tick.to;
        _synced = true;
        _ticks.add(tick);
    }
    _changes.add(null);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _ticks.close();
    await _changes.close();
    await _catalogChanges.close();
  }
}
