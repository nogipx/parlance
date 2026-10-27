import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';

import '../participant/local.dart';
import '../participant/participant.dart';
import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/types.dart';
import 'contract.dart';

// --- The registry's side -------------------------------------------------------

/// A participant served across a connection (SPEC §14, §22): `main` makes
/// it as it makes one for a module in this process (who it is, its
/// vocabularies, its rights, its access by default), and [serve] gives it
/// to the part at the other end of the endpoint, a `RemoteParticipant`
/// there.
extension ServeParticipant on LocalParticipant {
  /// Serves this participant over [endpoint] (registering the session's
  /// contract on it): the part across it reads, calls and owns words as
  /// this participant, and nothing more. The participant is the session's
  /// from then on: [RemoteSession.close] withdraws it, its words with it.
  /// Only a new participant is served, and once: one served already, or
  /// one that defined, attached or guarded anything here, is refused
  /// ([StateError]). Its access by default is told to the part across.

  RemoteSession serve(
    RpcPeerEndpoint endpoint, {
    String? session,
    int feedBacklog = 256,
    int maxSubscription = 4096,
    LogScope? log,
  }) {
    takeForServing(this);
    final s = RemoteSession._(
      endpoint,
      this,
      session: session,
      feedBacklog: feedBacklog,
      maxSubscription: maxSubscription,
      log: log,
    );
    endpoint.registerServiceContract(s);
    return s;
  }
}

/// One session of a participant served across a connection
/// ([ServeParticipant.serve], SPEC §14, §22.4): the registry as the
/// participant may see and use it; and, in its [namespaces] and as far as
/// [rights] let it, an owner of words of its own, whose commands it serves
/// over the same connection. [close] it when the connection ends, so its
/// words go.
final class RemoteSession extends ParlanceContractPeer {
  RemoteSession._(
    super.endpoint,
    LocalParticipant participant, {
    String? session,
    this.feedBacklog = 256,
    this.maxSubscription = 4096,
    LogScope? log,
  }) : session = session ?? newId(),
       registry = registryOf(participant),
       principal = participant.who,
       _owner = ParlanceOwnerContractPeerCaller(endpoint),
       _p = participant {
    this.log = (log ?? registry.log.child('sessions')).withData({
      'session': this.session,
      'principal': principal.selector,
    });
    if (this.log.isEnabled(RpcLogLevel.info)) this.log.info('session opened');
  }

  /// Where the session logs: when it opens and ends, what it was denied;
  /// the registry's `sessions` unless given.
  late final LogScope log;

  final Registry registry;

  /// How many items a feed holds for a client slower than the registry
  /// (SPEC §14): past it, the ticks held are dropped and the feed takes up
  /// again from the last one sent, as the registry still has it, or from a
  /// snapshot.
  final int feedBacklog;

  /// How long past its deadline a call of the session's own command waits
  /// for the owner's late end (SPEC §9): after it, the call ends `failed`.
  static const lateEnds = Duration(minutes: 5);

  /// How many names one subscription may ask for, states and facts
  /// together: a peer naming more is refused (`resourceExhausted`), so a
  /// session holds no more for it than this.
  final int maxSubscription;

  /// Who the session acts for; fixed when the host accepted the connection.
  final Principal principal;
  final String session;

  /// The session as a participant in this process: what it defines, writes
  /// and says goes through it, in its namespaces and with its rights.
  final LocalParticipant _p;

  Set<String> get namespaces => _p.namespaces;
  ParticipantRights get rights => _p.rights;

  /// The participant's side, serving the session's commands.
  final ParlanceOwnerContractPeerCaller _owner;

  final Map<String, IStateHandle> _states = {};
  final Map<String, IFactHandle> _facts = {};
  final Map<String, IHandle> _commands = {};
  final Map<String, IFactHandle> _producers = {};

  /// Why each of its commands cannot run now, as the participant told.
  final Map<String, String> _unavailable = {};

  /// Its entity kinds, with the entities it sent last.
  final Map<
    String,
    ({IHandle handle, List<EntityRef> entities, LocalParticipant part})
  >
  _kinds = {};

  /// Its guards, asked across the connection.
  final Map<String, IHandle> _guards = {};

  /// The calls of its commands it is serving now, by id.
  final Map<String, CommandCall> _serving = {};
  bool _closed = false;

  void _open() {
    if (_closed) {
      throw RpcStatusException(RpcStatus.unavailable, 'the session ended');
    }
  }

  Never _deny(String why) {
    if (log.isEnabled(RpcLogLevel.info)) log.info('denied', data: {'why': why});
    throw RpcStatusException(RpcStatus.permissionDenied, why);
  }

  /// The cause of what the session does: following from [parent] (a call
  /// it serves, or a fact the registry still keeps), else a new chain.
  Cause _cause({String? parent, Principal? by}) {
    final who = by ?? principal;
    if (parent != null) {
      if (_serving[parent] case final c?) return c.causeFor(who);
      if (registry.recentFact(parent) case final f? when _reads(f.fact)) {
        return f.cause.child(f.id, by: who);
      }
    }
    return Cause(who);
  }

  @override
  Future<WireDescription> onDescribe(
    RpcNull request, {
    RpcContext? context,
  }) async {
    _open();
    // What this session may call: so its clients offer only that.
    return WireDescription({
      ...registry.describeFor(principal),
      'protocol': parlanceProtocol,
      'principal': principal.toJson(),
      'namespaces': [..._p.namespaces],
      // Who may read and call its words by default, as the host said: the
      // part across fills its words' descriptors so.
      'defaults': {
        'read': ?_p.access.read?.toJson(),
        'call': ?_p.access.call?.toJson(),
      },
    });
  }

  @override
  Future<WireJson> onWhy(WireWhyRequest request, {RpcContext? context}) async {
    _open();
    if (registry.stateDescriptor(request.state) == null) {
      throw RpcStatusException(RpcStatus.notFound, 'no state ${request.state}');
    }
    if (!_reads(request.state)) _deny(_unreadable(request.state));
    registry.usedBy(request.state, principal);
    return WireJson(registry.explain(request.state, key: request.key).toJson());
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

  /// The feeds open now, each by what sends to it.
  final Set<void Function(WireFeedItem)> _feeds = {};

  /// The highest seq a call of the session answered at: what its mirror
  /// waits to reach before the call returns there.
  int _owed = 0;

  /// Each feed's catch-up: told the seq of a call answered.
  final Set<void Function(int seq)> _catchUps = {};

  /// How each feed open now is ended, when the session is.
  final Map<StreamController<WireFeedItem>, Future<void> Function()> _feedEnds =
      {};

  /// The states the session's feeds carry; null for all.
  Set<String>? get states =>
      _stateFilter == null ? null : Set.unmodifiable(_stateFilter!);

  /// The facts the session's feeds carry; null for all.
  Set<String>? get facts =>
      _factFilter == null ? null : Set.unmodifiable(_factFilter!);

  /// Whether the session hears a fact that [fact] matches: its feeds carry
  /// it (without a subscription, every fact it may hear), or it read the
  /// recent of it.
  bool hears(bool Function(String fact) fact) =>
      (_factFilter ??
              [
                for (final d in registry.catalog)
                  if (d is FactDescriptor && _reads(d.name)) d.name,
              ])
          .any(fact) ||
      _read.any(fact);

  /// Whether the session may read state [name]'s values, or hear fact
  /// [name] (its `readers`).
  bool _reads(String name) => registry.mayRead(principal, name);

  String _unreadable(String name) => '${principal.selector} may not read $name';

  bool _carries(String state) =>
      (_stateFilter?.contains(state) ?? true) && _reads(state);

  @override
  Stream<WireFeedItem> onFeed(WireFeedRequest request, {RpcContext? context}) {
    _open();
    late StreamController<WireFeedItem> out;
    StreamSubscription<FeedItem>? items;
    StreamSubscription<CatalogChange>? catalog;
    // The last seq the feed took: a tick it takes starts after it, so a
    // tick left out (nothing in it the session follows) leaves no gap.
    var last = request.since;
    // The last seq it handed to the connection, and of which epoch: the
    // client's until the feed hands it one of this registry's.
    var sent = request.since;
    var sentEpoch = request.epoch;
    // The last seq of a tick it saw, sent or left out.
    int? seen;
    // The commands that could not run when the feed last told, and why.
    var unavailable = const <String, String>{};
    // What waits while the connection is not taking more: it applies
    // backpressure, so a slow client pauses the feed. Ticks carry their
    // seq; held past [feedBacklog], they are dropped.
    final held = <(WireFeedItem, int?)>[];
    var behind = false;
    var factsDropped = false;

    void hand((WireFeedItem, int?) i) {
      out.add(i.$1);
      if (i.$2 case final seq?) {
        sent = seq;
        sentEpoch = registry.epoch;
      }
    }

    late void Function() follow;

    // Too far behind: what it holds of ticks goes, the rest stays (the
    // catalog last told, a subscription's values), and the feed follows
    // again from the last seq sent once the client takes more.
    void drop() {
      factsDropped |= held.any(
        (i) =>
            i.$1.kind == 'tick' &&
            (i.$1.json['facts'] as List? ?? const []).isNotEmpty,
      );
      // Of the catalog and of what cannot run, only the last told counts.
      final lastOf = {
        for (final i in held)
          if (i.$1.kind == 'catalog' || i.$1.kind == 'unavailable')
            i.$1.kind: i,
      };
      held.retainWhere((i) => i.$1.kind == 'values' || lastOf[i.$1.kind] == i);
      if (!behind) {
        behind = true;
        unawaited(items?.cancel());
        items = null;
      }
    }

    void send(WireFeedItem item, [int? seq]) {
      if (!out.isPaused && held.isEmpty) return hand((item, seq));
      held.add((item, seq));
      if (held.length > feedBacklog) drop();
    }

    // Tells the client, by an empty tick, that the ticks it was not sent
    // went by up to [seq]: a call answered there returns at once rather
    // than wait for a tick that never comes.
    void catchUp(int seq) {
      final through = seen;
      final from = last;
      if (through == null || from == null || from >= seq) return;
      final to = through < seq ? through : seq;
      if (to <= from) return;
      last = to;
      send(
        WireFeedItem(
          'tick',
          Tick(
            epoch: registry.epoch,
            from: from + 1,
            to: to,
            changes: const [],
            facts: const [],
          ).toJson(),
        ),
        to,
      );
    }

    void drain() {
      while (held.isNotEmpty && !out.isPaused) {
        hand(held.removeAt(0));
      }
      if (held.isEmpty && behind && !out.isPaused) {
        behind = false;
        last = sent;
        follow();
      }
    }

    void describe() {
      final d = registry.describeFor(principal);
      unavailable = d['unavailable']! as Map<String, String>;
      send(WireFeedItem('catalog', d));
    }

    // After a tick: whether a command came to run or stopped, told as the
    // whole set when it moved.
    void availability() {
      final now = registry.unavailable;
      if (_sameMap(now, unavailable)) return;
      unavailable = now;
      send(WireFeedItem('unavailable', {'unavailable': now}));
    }

    follow = () {
      items = registry.feed(epoch: sentEpoch, since: sent).listen((i) {
        switch (i) {
          case Snapshot():
            last = i.seq;
            send(
              WireFeedItem('snapshot', {
                ...Snapshot(
                  epoch: i.epoch,
                  seq: i.seq,
                  states: {
                    for (final e in i.states.entries)
                      if (_carries(e.key)) e.key: e.value,
                  },
                  factsLost: i.factsLost || factsDropped,
                ).toJson(),
                'subscription': _subscription,
              }),
              i.seq,
            );
            factsDropped = false;
          case Tick():
            seen = i.to;
            final t = _tickOf(i, last == null ? i.from : last! + 1);
            if (t != null) {
              last = i.to;
              send(WireFeedItem('tick', t.toJson()), i.to);
            } else if (i.to <= _owed) {
              // Nothing in it the session follows, but a call of its
              // waits for this seq: told it went by, empty.
              catchUp(i.to);
            }
            availability();
        }
      });
    };

    out = StreamController<WireFeedItem>(
      onListen: () {
        _feeds.add(send);
        _catchUps.add(catchUp);
        describe();
        catalog = registry.catalogChanges.listen((_) => describe());
        follow();
      },
      onResume: drain,
      onCancel: () async {
        _feeds.remove(send);
        _catchUps.remove(catchUp);
        _feedEnds.remove(out);
        held.clear();
        await items?.cancel();
        await catalog?.cancel();
      },
    );
    _feedEnds[out] = () async {
      _feeds.remove(send);
      _catchUps.remove(catchUp);
      held.clear();
      await items?.cancel();
      await catalog?.cancel();
      await out.close();
    };
    return out.stream;
  }

  /// [t] as the session follows it, from [from]; null when it has nothing
  /// the session follows.
  Tick? _tickOf(Tick t, int from) {
    final facts = _factFilter;
    final changes = [
      for (final c in t.changes)
        if (_carries(c.state)) c,
    ];
    final said = [
      for (final f in t.facts)
        if ((facts?.contains(f.fact) ?? true) && _reads(f.fact)) f,
    ];
    if (changes.isEmpty && said.isEmpty) return null;
    if (from == t.from &&
        changes.length == t.changes.length &&
        said.length == t.facts.length) {
      return t;
    }
    return Tick(
      epoch: t.epoch,
      from: from,
      to: t.to,
      changes: changes,
      facts: said,
    );
  }

  @override
  Future<WireJson> onSubscribe(
    WireSubscribe request, {
    RpcContext? context,
  }) async {
    _open();
    final asked = (request.states?.length ?? 0) + (request.facts?.length ?? 0);
    if (asked > maxSubscription) {
      throw RpcStatusException(
        RpcStatus.resourceExhausted,
        'a subscription asks for at most $maxSubscription names, not $asked',
      );
    }
    // A word it may not read is left out, not the whole subscription: one
    // such word among what its listeners ask for would otherwise hold back
    // every word added after it. Its status tells the participant why.
    final states = request.states?.where(_reads).toSet();
    final facts = request.facts?.where(_reads).toSet();
    final n = ++_subscription;
    _listenTo({...?states, ...?facts});
    final before = _stateFilter;
    // An old name of a word subscribes to the word (SPEC §6.4).
    final now = states?.map(registry.canonical).toSet();
    _stateFilter = now;
    _factFilter = facts?.map(registry.canonical).toSet();
    // The states the feeds carry now and did not: their values, so a copy
    // has them from here on, as the ticks after keep them.
    final added = before == null
        ? const <String>[]
        : [
            for (final name in now ?? _stateNames())
              if (!before.contains(name) &&
                  registry.stateDescriptor(name) != null &&
                  _reads(name))
                name,
          ];
    final item = WireFeedItem('values', {
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
    for (final send in _feeds) {
      send(item);
    }
    return WireJson({
      'subscription': n,
      // What it asked for and may not read: left out.
      'left': [
        for (final name in [...?request.states, ...?request.facts])
          if (!_reads(name)) name,
      ],
    });
  }

  /// What the session listens to, by the names it gave: counted as its use
  /// of each word (SPEC §6.8), from one subscription to the next.
  /// A name with no word yet is kept as null, and counted once its word
  /// comes ([_catalogChanged]).
  final Map<String, IHandle?> _listening = {};
  StreamSubscription<CatalogChange>? _catalogUse;

  void _listenTo(Set<String> names) {
    for (final gone in [..._listening.keys.where((n) => !names.contains(n))]) {
      _listening.remove(gone)?.dispose();
    }
    for (final name in names) {
      _listening[name] ??= registry.listenedBy(name, principal);
    }
    final waiting = _listening.containsValue(null);
    if (waiting && _catalogUse == null) {
      _catalogUse = registry.catalogChanges.listen(_catalogChanged);
    }
  }

  /// A word came, or an old name of one: the names it listens to that
  /// were not words before count from now.
  void _catalogChanged(CatalogChange c) {
    if (c is! DescriptorAdded && c is! AliasChanged) return;
    for (final name in [..._listening.keys]) {
      _listening[name] ??= registry.listenedBy(name, principal);
    }
    if (!_listening.containsValue(null)) {
      unawaited(_catalogUse?.cancel());
      _catalogUse = null;
    }
  }

  Iterable<String> _stateNames() => [
    for (final d in registry.catalog)
      if (d is StateDescriptor) d.name,
  ];

  @override
  Future<WireCallReply> onInvoke(
    WireCallRequest request, {
    RpcContext? context,
  }) async {
    _open();
    // Ids are the principal's own: another principal reusing one does not
    // get this one's answer.
    // A part of the session calls as itself (SPEC §22.3).
    final by = _part(request.as).who;
    final result = await registry.call(
      request.command,
      request.params,
      by: by,
      id: '${principal.selector}#${request.id}',
      override: request.overriding,
      cause: _cause(parent: request.parent, by: by),
    );
    final seq = registry.seq;
    if (seq > _owed) _owed = seq;
    for (final catchUp in [..._catchUps]) {
      catchUp(seq);
    }
    return WireCallReply(result.toJson(), epoch: registry.epoch, seq: seq);
  }

  @override
  Future<WireJson> onRecent(
    WireRecentRequest request, {
    RpcContext? context,
  }) async {
    _open();
    if (registry.factDescriptor(request.fact) == null) {
      throw RpcStatusException(RpcStatus.notFound, 'no fact ${request.fact}');
    }
    if (!_reads(request.fact)) _deny(_unreadable(request.fact));
    _read.add(request.fact);
    registry.usedBy(request.fact, principal);
    return WireJson({
      'facts': [
        for (final f in registry.recent(
          request.fact,
          request.count.clamp(0, registry.recentPerFact),
        ))
          f.toJson(),
      ],
    });
  }

  @override
  Future<RpcNull> onDefine(WireDefine request, {RpcContext? context}) async {
    _open();
    _define(_descriptor(request.descriptor));
    return const RpcNull();
  }

  @override
  Future<RpcNull> onUndefine(WireName request, {RpcContext? context}) async {
    _open();
    _undefine(request.name);
    return const RpcNull();
  }

  @override
  Future<RpcNull> onWrite(WireSet request, {RpcContext? context}) async {
    _open();
    _write(
      request.state,
      key: request.key,
      value: request.value,
      remove: request.remove,
      parent: request.parent,
    );
    return const RpcNull();
  }

  @override
  Future<WireTaken> onEmit(WireEmit request, {RpcContext? context}) async {
    _open();
    return WireTaken(
      _emit(
        request.fact,
        request.payload,
        id: request.id,
        by: request.by == null ? null : _principal(request.by),
        parent: request.parent,
      ),
    );
  }

  /// What a remote participant asked, in its order, as one tick (SPEC
  /// §22.4): each op answered on its own, a refusal of one not stopping
  /// the others.
  @override
  Future<WireJson> onApply(WireJson request, {RpcContext? context}) async {
    _open();
    final results = <Map<String, Object?>>[];
    registry.batch(() {
      for (final op in request.json['ops'] as List? ?? const []) {
        try {
          results.add(_op((op as Map).cast<String, Object?>()));
        } on RpcStatusException catch (e) {
          results.add({'error': e.statusCode.name, 'message': e.message});
        } on Object catch (e) {
          // An op that is not one (a field of the wrong type, a name that
          // is no name) is refused alone: the ops around it stand.
          results.add({
            'error': RpcStatus.invalidArgument.name,
            'message': '$e',
          });
        }
      }
    });
    return WireJson({'results': results});
  }

  /// The part of the session's principal [as] names (SPEC §22.3); the
  /// session itself for none. Anything but a part of it is refused.
  LocalParticipant _part(Object? as) {
    if (as == null) return _p;
    final who = _principal(as);
    if (who == principal) return _p;
    if (!who.isWithin(principal)) _deny('$who is no part of $principal');
    final rest = principal.id.isEmpty
        ? who.id
        : who.id.substring(principal.id.length + 1);
    var p = _p;
    for (final name in rest.split('/')) {
      p = p.child(name);
    }
    return p;
  }

  Map<String, Object?> _op(Map<String, Object?> m) {
    final part = _part(m['as']);
    switch (m['op']) {
      case 'define':
        _define(_descriptor(_obj(m['descriptor'])), part);
      case 'undefine':
        _undefine(m['name']! as String);
      case 'set' || 'remove':
        _write(
          m['state']! as String,
          key: m['key'] as String?,
          value: m['value'],
          remove: m['op'] == 'remove',
          parent: m['parent'] as String?,
          part: part,
        );
      case 'emit':
        return {
          'taken': _emit(
            m['fact']! as String,
            m['payload'],
            id: m['id'] as String?,
            by: m['by'] == null ? null : _principal(m['by']),
            parent: m['parent'] as String?,
            part: part,
          ),
        };
      case 'available':
        _available(m['command']! as String, m['why'] as String?);
      case 'kind':
        _kind(m['name']! as String, m['entities'] as List? ?? const [], part);
      case 'unkind':
        _kinds.remove(m['name'])?.handle.dispose();
      case 'guard':
        _guard(
          m['id']! as String,
          overridable: m['overridable'] != false,
          part: part,
        );
      case 'unguard':
        _guards.remove('${part.who.selector}#${m['id']}')?.dispose();
      default:
        throw RpcStatusException(RpcStatus.invalidArgument, 'no op ${m['op']}');
    }
    return const {};
  }

  /// The principal a peer named in [json], or `invalidArgument`.
  static Principal _principal(Object? json) {
    try {
      return Principal.fromJson(json);
    } on Object catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, 'no principal: $e');
    }
  }

  static Map<String, Object?> _obj(Object? v) =>
      (v as Map? ?? const {}).cast<String, Object?>();

  static Descriptor _descriptor(Map<String, Object?> json) {
    try {
      return Descriptor.fromJson(json);
    } on Object catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '$e');
    }
  }

  /// [f], with a participant's refusal as `permissionDenied`.
  T _permitted<T>(T Function() f) {
    try {
      return f();
    } on NotPermitted catch (e) {
      _deny(e.message);
    }
  }

  void _define(Descriptor d, [LocalParticipant? part]) {
    final p = part ?? _p;
    try {
      _permitted(() {
        switch (d) {
          case StateDescriptor():
            _states[d.name] = p.defineState(d);
          case FactDescriptor():
            _facts[d.name] = p.defineFact(d);
          case CommandDescriptor():
            _commands[d.name] = p.defineCommand(
              d,
              _serve,
              available: () => _unavailable[d.name],
            );
          case QueryDescriptor():
            _commands[d.name] = p.defineQuery(
              d,
              _serve,
              available: () => _unavailable[d.name],
            );
        }
      });
    } on StateError catch (e) {
      throw RpcStatusException(RpcStatus.alreadyExists, e.message);
    }
  }

  void _undefine(String name) {
    final h =
        _states.remove(name) ?? _facts.remove(name) ?? _commands.remove(name);
    if (h == null) {
      throw RpcStatusException(
        RpcStatus.notFound,
        'the session defined no $name',
      );
    }
    _unavailable.remove(name);
    h.dispose();
  }

  void _write(
    String state, {
    String? key,
    Object? value,
    bool remove = false,
    String? parent,
    LocalParticipant? part,
  }) {
    final w = _states[state];
    if (w == null) {
      if (registry.stateDescriptor(state) == null) {
        throw RpcStatusException(RpcStatus.notFound, 'no state $state');
      }
      _deny('$state is not the session\'s own');
    }
    final cause = _cause(parent: parent, by: (part ?? _p).who);
    try {
      remove
          ? w.remove(key: key, cause: cause)
          : w.set(value, key: key, cause: cause);
    } on TypeMismatch catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '$e');
    } on ArgumentError catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '${e.message}');
    }
  }

  bool _emit(
    String fact,
    Object? payload, {
    String? id,
    Principal? by,
    String? parent,
    LocalParticipant? part,
  }) {
    final p = part ?? _p;
    var e = _facts[fact];
    if (e == null) {
      final d = registry.factDescriptor(fact);
      if (d == null) {
        throw RpcStatusException(RpcStatus.notFound, 'no fact $fact');
      }
      if (!d.open) _deny('$fact is not open');
      e = _producers['${p.who.selector}|$fact'] ??= _permitted(
        () => p.producer(fact),
      );
    }
    final emitter = e;
    try {
      return _permitted(
        () => emitter.emit(
          payload,
          id: id == null ? null : '${principal.selector}#$id',
          cause: _cause(parent: parent, by: by ?? p.who),
        ),
      );
    } on TypeMismatch catch (x) {
      throw RpcStatusException(RpcStatus.invalidArgument, '$x');
    } on StateError catch (x) {
      _producers.remove('${p.who.selector}|$fact');
      throw RpcStatusException(RpcStatus.notFound, x.message);
    }
  }

  void _available(String command, String? why) {
    if (!_commands.containsKey(command)) {
      _deny('$command is not the session\'s own');
    }
    if (_unavailable[command] == why) return;
    why == null ? _unavailable.remove(command) : _unavailable[command] = why;
    registry.availabilityChanged(command);
  }

  void _kind(String name, List<Object?> entities, [LocalParticipant? part]) {
    final list = [
      for (final e in entities.cast<Map<Object?, Object?>>())
        EntityRef(e['id']! as String, e['label'] as String?, _obj(e['meta'])),
    ];
    if (_kinds[name] case final k?) {
      _kinds[name] = (handle: k.handle, entities: list, part: k.part);
      _permitted(() => k.part.entitiesChanged(name));
      return;
    }
    final p = part ?? _p;
    try {
      final handle = p.registerKind(
        EntityKind(name, list: () => _kinds[name]?.entities ?? const []),
      );
      _kinds[name] = (handle: handle, entities: list, part: p);
    } on StateError catch (e) {
      throw RpcStatusException(RpcStatus.alreadyExists, e.message);
    }
  }

  /// A guard of the session's or a part's, on its commands only, asked in
  /// its turn: the participant judges the call. Known as `<speaker>/<id>`.
  void _guard(String id, {required bool overridable, LocalParticipant? part}) {
    final p = part ?? _p;
    final full = '${p.who.selector}#$id';
    try {
      _guards[full] = p.addAskedGuard(full, (c) async {
        final r = await _owner.judge(
          WireJson({
            'guard': full,
            'id': c.id,
            'command': c.command.name,
            'params': c.params,
            'cause': c.cause.toJson(),
          }),
        );
        return r.json['why'] as String?;
      }, overridable: overridable);
    } on StateError catch (e) {
      throw RpcStatusException(RpcStatus.alreadyExists, e.message);
    }
  }

  /// Serves a call of a command of the session's: the participant does.
  Future<Object?> _serve(CommandCall c) async {
    _serving[c.id] = c;
    try {
      final deadline = registry.callableDescriptor(c.command)?.deadline;
      final served = await _owner.serve(
        WireServe(
          id: c.id,
          command: c.command,
          params: c.params,
          cause: c.cause.toJson(),
          traceparent: c.span.traceparent,
        ),
        // The registry bounds the call by its deadline and answers
        // `timedOut`; the owner's late end is still waited for, and
        // recorded late, as a handler's in this process is, up to a while
        // past it (a peer cannot hold a call open for good).
        context: RpcContext.empty().withTimeout(
          (deadline ?? const Duration(seconds: 30)) + lateEnds,
        ),
      );
      if (served.error case final why?) throw _Failed(why);
      return served.value;
    } on RpcStatusException catch (e) {
      throw _Failed('its owner did not answer: ${e.message}');
    } finally {
      _serving.remove(c.id);
    }
  }

  /// Ends the session: its words go, its calls are refused.
  void close() {
    if (_closed) return;
    _closed = true;
    if (log.isEnabled(RpcLogLevel.info)) log.info('session closed');
    unawaited(_catalogUse?.cancel());
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
    _kinds.clear();
    _guards.clear();
    _unavailable.clear();
    _listenTo(const {});
    _p.dispose();
    // Its feeds end: nothing more goes to a session that ended.
    for (final end in [..._feedEnds.values]) {
      unawaited(end());
    }
    _feedEnds.clear();
  }
}

/// Why a remote owner's command failed, in its words.
final class _Failed implements Exception {
  const _Failed(this.why);
  final String why;

  @override
  String toString() => why;
}

bool _sameMap(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

// --- The participant's side ----------------------------------------------------

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

  /// The deadline of a request the registry answers at once (describe,
  /// why, recent facts), without a context of its own.
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
            WireFeedRequest(epoch: epoch, since: since),
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
              'unavailable' => RemoteUnavailable(
                (i.json['unavailable']! as Map).cast(),
              ),
              'tick' => RemoteTick(Tick.fromJson(i.json)),
              // An item of a newer protocol this client does not know.
              _ => null,
            },
          )
          .where((i) => i != null)
          .cast();

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
    bool override = false,
    String? parent,
    RpcContext? context,
  }) async => (await callAt(
    command,
    params,
    id: id,
    override: override,
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
          overriding: override,
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

  /// Why [state] (of [key]) is as it is (Registry.explain).
  Future<Explanation> why(
    String state, {
    String? key,
    RpcContext? context,
  }) async => Explanation.fromJson(
    (await _caller.why(
      WireWhyRequest(state, key: key),
      context: _ctx(context),
    )).json,
  );

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
  /// op: `{}`, `{taken}` for an emit, or `{error, message}`.
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
  Future<bool> emit(
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
final class RemoteOwner extends ParlanceOwnerContractPeer {
  RemoteOwner(super.endpoint, this.client);

  final ParlanceClient client;
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

  /// It keeps no guards: every call it is asked about passes.
  @override
  Future<WireJson> onJudge(WireJson request, {RpcContext? context}) async =>
      const WireJson({});

  @override
  Future<WireServed> onServe(WireServe request, {RpcContext? context}) async {
    final handler = _handlers[request.command];
    if (handler == null) {
      return WireServed.failed('nothing serves ${request.command}');
    }
    try {
      return WireServed.done(
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
      return WireServed.failed('$e');
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
  ParlanceClient? _client;
  StreamSubscription<RemoteFeed>? _sub;
  bool _synced = false;
  final StreamController<Tick> _ticks = StreamController.broadcast();
  final StreamController<void> _changes = StreamController.broadcast();
  final StreamController<void> _catalogChanges = StreamController.broadcast();
  final StreamController<void> _statusChanges = StreamController.broadcast();

  /// From the catalog: each word's kind by name, the words the session's
  /// principal may not read or call, the commands that cannot run now.
  Map<String, String> _words = const {};
  Set<String> _closed = const {};
  Map<String, String> _unavailable = const {};

  String? get epoch => _epoch;
  int get seq => _seq;

  /// The catalog as the session's principal sees it (`describeFor`).
  Map<String, Object?> get catalog => _catalog;

  /// Whether the session's principal can use the word [name] now (SPEC
  /// §6.5), as the catalog and the availability the feed brought last say.
  WordStatus statusOf(String name) {
    final n = canonical(name);
    final kind = _words[n];
    if (kind == null) return const WordMissing();
    if (_closed.contains(n)) return const WordNotPermitted();
    if (kind == 'command' || kind == 'query') {
      if (_unavailable[n] case final why?) return WordUnavailable(why);
    }
    return const WordReady();
  }

  /// The catalog came, or a command came to run or stopped: a word's
  /// [statusOf] may have changed.
  Stream<void> get statusChanges => _statusChanges.stream;

  /// Whether the copy follows the registry now.
  bool get synced => _synced;

  /// The ticks applied, in order.
  Stream<Tick> get ticks => _ticks.stream;

  /// Something changed: a snapshot, a tick, the catalog, the connection.
  Stream<void> get changes => _changes.stream;

  /// The catalog came: first after following, and on every change of it
  /// (descriptors or entities).
  Stream<void> get catalogChanges => _catalogChanges.stream;

  Object? read(String state, {String? key}) => _states[canonical(state)]?[key];

  /// The name [name] stands for, as the catalog's `aliases` say.
  String canonical(String name) => switch (_catalog['aliases']) {
    final Map<Object?, Object?> a when a[name] is String => a[name]! as String,
    _ => name,
  };

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
      Map.unmodifiable(_states[canonical(state)] ?? const {});

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
  void follow(ParlanceClient client) {
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

  /// Takes [json], the catalog as the session's principal sees it
  /// (`describe` answers it too), as the one it has now.
  void takeCatalog(Map<String, Object?> json) {
    _catalog = json;
    _words = {
      for (final d in json['descriptors'] as List? ?? const [])
        (d as Map)['name'] as String: d['is'] as String,
    };
    _closed = {
      ...?(json['unreadable'] as List?)?.cast<String>(),
      for (final e in (json['access'] as Map? ?? const {}).entries)
        if (e.value == Access.deny.name) e.key as String,
    };
    _unavailable = (json['unavailable'] as Map? ?? const {}).cast();
    // The values of a state that left the catalog go with it, though no
    // tick removed them.
    _states.removeWhere((name, _) => _words[name] != 'state');
    _catalogChanges.add(null);
    _statusChanges.add(null);
  }

  void _apply(RemoteFeed item) {
    switch (item) {
      case RemoteCatalog(:final json):
        takeCatalog(json);
        // A feed resumed in the same epoch carries on from the copy's seq:
        // the copy follows again from its first item, though nothing may
        // have happened since to send.
        if (_epoch != null && json['epoch'] == _epoch) _synced = true;
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
      case RemoteUnavailable(:final unavailable):
        _unavailable = unavailable;
        _statusChanges.add(null);
        return;
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
    await _statusChanges.close();
  }
}
