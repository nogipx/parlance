import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';

import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/types.dart';
import 'contract.dart';

// --- The registry's side -------------------------------------------------------

/// What a session may own besides calling and holding layers (SPEC §14):
/// the host's to say, for the principal it accepted. Each answers null when
/// the session may, else why not; an absent one lets no session.
final class SessionRights {
  const SessionRights({this.define, this.produce, this.speakFor});

  /// Define [d] (a state, a command or a fact) as the session's own.
  final String? Function(Principal session, Descriptor d)? define;

  /// Say [fact], an open fact another defined.
  final String? Function(Principal session, String fact)? produce;

  /// Say [fact] on behalf of [by]: its cause is theirs, and so are the
  /// rights of what follows from it.
  final String? Function(Principal session, Principal by, String fact)?
  speakFor;

  /// A session that only calls and holds layers.
  static const none = SessionRights();
}

/// One session of a remote participant (SPEC §14): the registry as the
/// principal the host accepted for this connection may see and use it; and,
/// as far as [rights] let it, an owner of words of its own, whose commands
/// it serves over the same connection.
///
/// Register it on the connection's peer endpoint; [close] it when the
/// connection ends, so its layers and its words go.
final class RegistryResponder extends SwitchboardContractPeer {
  RegistryResponder(
    super.endpoint,
    this.registry, {
    required this.principal,
    String? session,
    this.rights = SessionRights.none,
  }) : session = session ?? newId(),
       _owner = SwitchboardOwnerContractPeerCaller(endpoint);

  final Registry registry;

  /// Who the session acts for; fixed when the host accepted the connection.
  final Principal principal;
  final String session;
  final SessionRights rights;

  /// The participant's side, serving the session's commands.
  final SwitchboardOwnerContractPeerCaller _owner;

  /// The owner of the layers the session pushes.
  String get owner => 'remote:$session';

  final Map<String, LayerHandle> _layers = {};
  final Map<String, StateWriter> _states = {};
  final Map<String, FactEmitter> _facts = {};
  final Map<String, Handle> _commands = {};
  final Map<String, FactEmitter> _producers = {};

  /// The calls of its commands it is serving now, by id.
  final Map<String, CommandCall> _serving = {};
  bool _closed = false;

  void _open() {
    if (_closed) {
      throw RpcStatusException(RpcStatus.unavailable, 'the session ended');
    }
  }

  static Never _deny(String why) =>
      throw RpcStatusException(RpcStatus.permissionDenied, why);

  /// The cause of what the session does: following from [parent] (a call
  /// it serves, or a fact the registry still keeps), else a new chain.
  Cause _cause({String? parent, bool test = false, Principal? by}) {
    final who = by ?? principal;
    if (parent != null) {
      if (_serving[parent] case final c?) return c.causeFor(who);
      if (registry.recentFact(parent) case final f?) {
        return f.cause.child(f.id, by: who);
      }
    }
    return Cause(who, test: test);
  }

  @override
  Future<SbDescription> onDescribe(
    RpcNull request, {
    RpcContext? context,
  }) async {
    _open();
    // What this session may call: so its clients offer only that.
    return SbDescription({
      ...registry.describeFor(principal),
      'protocol': switchboardProtocol,
    });
  }

  @override
  Future<SbJson> onWhy(SbWhyRequest request, {RpcContext? context}) async {
    _open();
    if (registry.stateDescriptor(request.state) == null) {
      throw RpcStatusException(RpcStatus.notFound, 'no state ${request.state}');
    }
    return SbJson(registry.explain(request.state, key: request.key).toJson());
  }

  @override
  Future<SbJson> onLayers(RpcNull request, {RpcContext? context}) async {
    _open();
    return SbJson({
      'layers': [for (final l in registry.layers()) l.toJson()],
    });
  }

  /// What the session's feeds carry ([onSubscribe]): these states and
  /// facts; null for all of them.
  Set<String>? _stateFilter;
  Set<String>? _factFilter;

  /// How many times the session subscribed; a feed's `values` item and its
  /// snapshot carry the number it follows.
  int _subscription = 0;

  /// The facts the session read the recent of.
  final Set<String> _read = {};

  /// The feeds open now.
  final Set<StreamController<SbFeedItem>> _feeds = {};

  /// The states the session's feeds carry; null for all.
  Set<String>? get states =>
      _stateFilter == null ? null : Set.unmodifiable(_stateFilter!);

  /// The facts the session's feeds carry; null for all.
  Set<String>? get facts =>
      _factFilter == null ? null : Set.unmodifiable(_factFilter!);

  /// Whether the session hears a fact that [fact] matches: its feeds carry
  /// it, or it read the recent of it.
  bool hears(bool Function(String fact) fact) =>
      _factFilter == null || _factFilter!.any(fact) || _read.any(fact);

  bool _carries(String state) => _stateFilter?.contains(state) ?? true;

  @override
  Stream<SbFeedItem> onFeed(SbFeedRequest request, {RpcContext? context}) {
    _open();
    late StreamController<SbFeedItem> out;
    StreamSubscription<FeedItem>? items;
    StreamSubscription<CatalogChange>? catalog;
    // The last seq the feed sent: a tick it sends starts after it, so a
    // tick left out (nothing in it the session follows) leaves no gap.
    var last = request.since;
    out = StreamController<SbFeedItem>(
      onListen: () {
        _feeds.add(out);
        out.add(SbFeedItem('catalog', registry.describe()));
        catalog = registry.catalogChanges.listen(
          (_) => out.add(SbFeedItem('catalog', registry.describe())),
        );
        items = registry
            .feed(epoch: request.epoch, since: request.since)
            .listen((i) {
              switch (i) {
                case Snapshot():
                  last = i.seq;
                  out.add(
                    SbFeedItem('snapshot', {
                      ...Snapshot(
                        epoch: i.epoch,
                        seq: i.seq,
                        states: {
                          for (final e in i.states.entries)
                            if (_carries(e.key)) e.key: e.value,
                        },
                        factsLost: i.factsLost,
                      ).toJson(),
                      'subscription': _subscription,
                    }),
                  );
                case Tick():
                  final t = _tickOf(i, last == null ? i.from : last! + 1);
                  if (t == null) return;
                  last = i.to;
                  out.add(SbFeedItem('tick', t.toJson()));
              }
            });
      },
      onCancel: () async {
        _feeds.remove(out);
        await items?.cancel();
        await catalog?.cancel();
      },
    );
    return out.stream;
  }

  /// [t] as the session follows it, from [from]; null when it has nothing
  /// the session follows.
  Tick? _tickOf(Tick t, int from) {
    final states = _stateFilter;
    final facts = _factFilter;
    if (states == null && facts == null) {
      return from == t.from
          ? t
          : Tick(
              epoch: t.epoch,
              from: from,
              to: t.to,
              changes: t.changes,
              facts: t.facts,
            );
    }
    final changes = [
      for (final c in t.changes)
        if (states?.contains(c.state) ?? true) c,
    ];
    final said = [
      for (final f in t.facts)
        if (facts?.contains(f.fact) ?? true) f,
    ];
    if (changes.isEmpty && said.isEmpty) return null;
    return Tick(
      epoch: t.epoch,
      from: from,
      to: t.to,
      changes: changes,
      facts: said,
    );
  }

  @override
  Future<SbJson> onSubscribe(SbSubscribe request, {RpcContext? context}) async {
    _open();
    final n = ++_subscription;
    final before = _stateFilter;
    final now = request.states?.toSet();
    _stateFilter = now;
    _factFilter = request.facts?.toSet();
    // The states the feeds carry now and did not: their values, so a copy
    // has them from here on, as the ticks after keep them.
    final added = before == null
        ? const <String>[]
        : [
            for (final name in now ?? _stateNames())
              if (!before.contains(name) &&
                  registry.stateDescriptor(name) != null)
                name,
          ];
    final item = SbFeedItem('values', {
      'subscription': n,
      'states': {
        for (final name in added)
          name: [
            for (final v in registry.readAll(name).entries)
              {'key': ?v.key, 'value': v.value},
          ],
      },
      'keep': ?now?.toList(),
    });
    for (final f in _feeds) {
      f.add(item);
    }
    return SbJson({'subscription': n});
  }

  Iterable<String> _stateNames() => [
    for (final d in registry.catalog)
      if (d is StateDescriptor) d.name,
  ];

  @override
  Future<SbCallReply> onInvoke(
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
      cause: _cause(parent: request.parent, test: request.test),
    );
    return SbCallReply(
      result.toJson(),
      epoch: registry.epoch,
      seq: registry.seq,
    );
  }

  @override
  Future<SbJson> onRecent(
    SbRecentRequest request, {
    RpcContext? context,
  }) async {
    _open();
    if (registry.factDescriptor(request.fact) == null) {
      throw RpcStatusException(RpcStatus.notFound, 'no fact ${request.fact}');
    }
    _read.add(request.fact);
    return SbJson({
      'facts': [
        for (final f in registry.recent(request.fact, request.count))
          f.toJson(),
      ],
    });
  }

  @override
  Future<SbLayerRef> onPushLayer(
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
      _deny('$principal may not set ${request.state}');
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
  Future<RpcNull> onPopLayer(SbLayerRef request, {RpcContext? context}) async {
    _open();
    final h = _layers.remove(request.layer);
    if (h == null) {
      throw RpcStatusException(RpcStatus.notFound, 'no layer ${request.layer}');
    }
    h.dispose();
    return const RpcNull();
  }

  @override
  Stream<SbLayerEvent> onLayerEvents(RpcNull request, {RpcContext? context}) {
    _open();
    return registry.layerEvents
        .where((e) => e.owner == owner)
        .map((e) => SbLayerEvent(e.toJson()));
  }

  @override
  Future<RpcNull> onDefine(SbDefine request, {RpcContext? context}) async {
    _open();
    final Descriptor d;
    try {
      d = Descriptor.fromJson(request.descriptor);
    } on Object catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '$e');
    }
    final check = rights.define;
    if ((check == null ? '$principal may define nothing' : check(principal, d))
        case final why?) {
      _deny(why);
    }
    try {
      switch (d) {
        case StateDescriptor():
          _states[d.name] = registry.defineState(d, by: principal);
        case FactDescriptor():
          _facts[d.name] = registry.defineFact(d, by: principal);
        case CommandDescriptor():
          _commands[d.name] = registry.defineCommand(d, _serve);
      }
    } on StateError catch (e) {
      throw RpcStatusException(RpcStatus.alreadyExists, e.message);
    }
    return const RpcNull();
  }

  @override
  Future<RpcNull> onUndefine(SbName request, {RpcContext? context}) async {
    _open();
    final h =
        _states.remove(request.name) ??
        _facts.remove(request.name) ??
        _commands.remove(request.name);
    if (h == null) {
      throw RpcStatusException(
        RpcStatus.notFound,
        'the session defined no ${request.name}',
      );
    }
    h.dispose();
    return const RpcNull();
  }

  @override
  Future<RpcNull> onWrite(SbSet request, {RpcContext? context}) async {
    _open();
    final w = _states[request.state];
    if (w == null) {
      if (registry.stateDescriptor(request.state) == null) {
        throw RpcStatusException(
          RpcStatus.notFound,
          'no state ${request.state}',
        );
      }
      _deny('${request.state} is not the session\'s own');
    }
    final cause = _cause(parent: request.parent, test: request.test);
    try {
      request.remove
          ? w.remove(key: request.key, cause: cause)
          : w.set(request.value, key: request.key, cause: cause);
    } on TypeMismatch catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '$e');
    } on ArgumentError catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '${e.message}');
    }
    return const RpcNull();
  }

  @override
  Future<SbTaken> onEmit(SbEmit request, {RpcContext? context}) async {
    _open();
    final fact = request.fact;
    final by = request.by == null ? null : Principal.fromJson(request.by);
    if (by != null && by != principal) {
      final check = rights.speakFor;
      if ((check == null
              ? '$principal may speak for no one'
              : check(principal, by, fact))
          case final why?) {
        _deny(why);
      }
    }
    var e = _facts[fact];
    if (e == null) {
      final d = registry.factDescriptor(fact);
      if (d == null) {
        throw RpcStatusException(RpcStatus.notFound, 'no fact $fact');
      }
      if (!d.open) _deny('$fact is not open');
      final check = rights.produce;
      if ((check == null
              ? '$principal may produce nothing'
              : check(principal, fact))
          case final why?) {
        _deny(why);
      }
      e = _producers[fact] ??= registry.producer(fact, by: principal);
    }
    try {
      return SbTaken(
        e.emit(
          request.payload,
          id: request.id == null ? null : '${principal.selector}/${request.id}',
          cause: _cause(parent: request.parent, test: request.test, by: by),
        ),
      );
    } on TypeMismatch catch (x) {
      throw RpcStatusException(RpcStatus.invalidArgument, '$x');
    } on StateError catch (x) {
      _producers.remove(fact);
      throw RpcStatusException(RpcStatus.notFound, x.message);
    }
  }

  /// Serves a call of a command of the session's: the participant does.
  Future<Object?> _serve(CommandCall c) async {
    _serving[c.id] = c;
    try {
      final deadline = registry.commandDescriptor(c.command)?.deadline;
      final served = await _owner.serve(
        SbServe(
          id: c.id,
          command: c.command,
          params: c.params,
          cause: c.cause.toJson(),
        ),
        context: deadline == null
            ? null
            : RpcContext.empty().withTimeout(deadline),
      );
      if (served.error case final why?) throw _Failed(why);
      return served.value;
    } on RpcStatusException catch (e) {
      throw _Failed('its owner did not answer: ${e.message}');
    } finally {
      _serving.remove(c.id);
    }
  }

  /// Ends the session: its layers and its words go, its calls are refused.
  void close() {
    if (_closed) return;
    _closed = true;
    _layers.clear();
    registry.dropLayersOf(owner);
    for (final h in [
      ..._commands.values,
      ..._facts.values,
      ..._states.values,
    ]) {
      h.dispose();
    }
    _commands.clear();
    _facts.clear();
    _states.clear();
    _producers.clear();
  }
}

/// Why a remote owner's command failed, in its words.
final class _Failed implements Exception {
  const _Failed(this.why);
  final String why;

  @override
  String toString() => why;
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
  const RemoteSnapshot(this.snapshot, {this.subscription = 0});
  final Snapshot snapshot;

  /// The session's subscription it follows ([SwitchboardClient.subscribe]).
  final int subscription;
}

final class RemoteTick extends RemoteFeed {
  const RemoteTick(this.tick);
  final Tick tick;
}

/// The session subscribed ([SwitchboardClient.subscribe]): the values of the
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
final class SwitchboardClient {
  SwitchboardClient(
    RpcPeerEndpoint endpoint, {
    this.timeout = const Duration(seconds: 10),
  }) : _caller = SwitchboardContractPeerCaller(endpoint);

  final SwitchboardContractPeerCaller _caller;

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
              'snapshot' => RemoteSnapshot(
                Snapshot.fromJson(i.json),
                subscription: i.json['subscription'] as int? ?? 0,
              ),
              'values' => RemoteValues.fromJson(i.json),
              _ => RemoteTick(Tick.fromJson(i.json)),
            },
          );

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
            SbSubscribe(states: states?.toList(), facts: facts?.toList()),
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
    bool override = false,
    bool test = false,
    String? parent,
    RpcContext? context,
  }) async => (await callAt(
    command,
    params,
    id: id,
    override: override,
    test: test,
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
    bool override = false,
    bool test = false,
    String? parent,
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
          parent: parent,
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

  /// Defines [d] as the session's own, as far as the host lets it. A
  /// command's calls come to the session's [RemoteOwner].
  Future<void> define(Descriptor d, {RpcContext? context}) =>
      _caller.define(SbDefine(d.toJson()), context: _ctx(context));

  Future<void> undefine(String name, {RpcContext? context}) =>
      _caller.undefine(SbName(name), context: _ctx(context));

  /// Writes [value] to the session's own [state] (of [key]), or [remove]s
  /// it.
  Future<void> write(
    String state, {
    String? key,
    Object? value,
    bool remove = false,
    String? parent,
    bool test = false,
    RpcContext? context,
  }) => _caller.write(
    SbSet(
      state: state,
      key: key,
      value: value,
      remove: remove,
      parent: parent,
      test: test,
    ),
    context: _ctx(context),
  );

  /// Says [fact]: the session's own, or an open one it produces; [by] when
  /// the host lets it say it for someone else. False when [id] was said
  /// already.
  Future<bool> emit(
    String fact,
    Object? payload, {
    String? id,
    Principal? by,
    String? parent,
    bool test = false,
    RpcContext? context,
  }) async => (await _caller.emit(
    SbEmit(
      fact: fact,
      payload: payload,
      id: id,
      by: by?.toJson(),
      parent: parent,
      test: test,
    ),
    context: _ctx(context),
  )).taken;
}

/// A call of a command the session owns, as its handler gets it.
final class RemoteCall {
  const RemoteCall(this.id, this.command, this.params, this.cause);

  /// What the handler's own calls and writes follow from (`parent:`).
  final String id;
  final String command;

  /// Checked by the registry, with defaults filled.
  final Map<String, Object?> params;
  final Cause cause;

  Principal get by => cause.by;
}

/// Serves a call of the session's command: its answer, of the command's
/// `returns`; a throw fails the call with its message.
typedef RemoteHandler = FutureOr<Object?> Function(RemoteCall call);

/// The participant's side of a session that owns words (SPEC §14): it
/// defines them through [client] and serves their calls. Register it on the
/// same peer endpoint as the client's.
final class RemoteOwner extends SwitchboardOwnerContractPeer {
  RemoteOwner(super.endpoint, this.client);

  final SwitchboardClient client;
  final Map<String, RemoteHandler> _handlers = {};

  /// Defines command [d], served by [handler].
  Future<void> defineCommand(CommandDescriptor d, RemoteHandler handler) async {
    _handlers[d.name] = handler;
    try {
      await client.define(d);
    } on Object {
      _handlers.remove(d.name);
      rethrow;
    }
  }

  Future<void> undefine(String name) async {
    await client.undefine(name);
    _handlers.remove(name);
  }

  @override
  Future<SbServed> onServe(SbServe request, {RpcContext? context}) async {
    final handler = _handlers[request.command];
    if (handler == null) {
      return SbServed.failed('nothing serves ${request.command}');
    }
    try {
      return SbServed.done(
        await handler(
          RemoteCall(
            request.id,
            request.command,
            request.params,
            Cause.fromJson(request.cause),
          ),
        ),
      );
    } on Object catch (e) {
      return SbServed.failed('$e');
    }
  }
}

/// A remote participant's copy of the registry's states, kept by a feed and
/// resumed after a lost connection without gaps or repeats (SPEC §12).
final class RegistryMirror {
  String? _epoch;
  int _seq = 0;

  /// The session's subscription the copy follows, and what it asked for.
  int _subscription = 0;
  ({Set<String>? states, Set<String>? facts})? _wanted;
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
  /// there. With a subscription the copy's seq moves only with the ticks
  /// its feed carries: a write to a state it does not keep is not waited
  /// for.
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

  /// The states the copy keeps, and the facts its ticks carry; null for
  /// all.
  Set<String>? get states => _wanted?.states;
  Set<String>? get facts => _wanted?.facts;

  /// Keeps only [states] and hears only [facts] (null: all of them);
  /// completes when the copy has the values of the states it keeps now, or
  /// after [timeout]. Kept over a new connection ([follow]).
  Future<void> subscribe({
    Set<String>? states,
    Set<String>? facts,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _wanted = (states: states, facts: facts);
    final client = _client;
    if (client == null) return;
    final n = await client.subscribe(states: states, facts: facts);
    if (_subscription >= n || _client != client) return;
    try {
      await changes
          .firstWhere((_) => _subscription >= n || _client != client)
          .timeout(timeout);
    } on TimeoutException {
      return;
    } on StateError {
      return;
    }
  }

  /// Follows [client]'s feed, resuming after what the copy already has.
  /// Call again with a new client after the connection was lost.
  void follow(SwitchboardClient client) {
    _client = client;
    _subscription = 0;
    if (_wanted case (:final states, :final facts)) {
      // A new session carries everything until it subscribes: before the
      // feed, so its snapshot has only what the copy keeps.
      unawaited(
        client
            .subscribe(states: states, facts: facts)
            .then((_) {}, onError: (Object _) {}),
      );
    }
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
      case RemoteSnapshot(:final snapshot, :final subscription):
        _subscription = subscription;
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
      case RemoteValues(:final subscription, :final states, :final keep):
        _subscription = subscription;
        if (keep != null) _states.removeWhere((k, _) => !keep.contains(k));
        for (final e in states.entries) {
          _states[e.key] = {...e.value};
        }
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
