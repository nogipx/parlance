import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';

import '../participant/local.dart';
import '../participant/participant.dart';
import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/json.dart' show jsonWeight;
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/types.dart';
import 'contract.dart';

part 'session_feed.dart';

/// A participant served across a connection (SPEC §14, §22): `main` makes
/// it as it makes one for a module in this process (who it is, its
/// vocabularies, its rights, its access by default), and [serve] gives it
/// to the part at the other end of the endpoint, a `RemoteParticipant`
/// there.
extension ServeParticipant on LocalParticipant {
  /// Serves this participant over [endpoint] (registering the session's
  /// contract on it): the part across it reads, calls and owns words as
  /// this participant, and nothing more. The participant is the session's
  /// from then on: [RemoteSession.dispose] withdraws it, its words with it.
  /// Only a new participant is served, and once: one served already, or
  /// one that defined, attached or guarded anything here, is refused
  /// ([StateError]). Its access by default is told to the part across, and
  /// what of the protocol it speaks ([RemoteSession.features]).
  RemoteSession serve(
    RpcPeerEndpoint endpoint, {
    String? session,
    int feedBacklog = 256,
    int maxSubscription = 4096,
    SessionLimits limits = const SessionLimits(),
    LogScope? log,
    Set<String>? features,
  }) {
    late final RemoteSession s;
    takeForServing(this, end: () => s._takenOver());
    s = RemoteSession._(
      endpoint,
      this,
      session: session,
      feedBacklog: feedBacklog,
      maxSubscription: maxSubscription,
      limits: limits,
      log: log,
      features: features,
    );
    endpoint.registerServiceContract(s);
    return s;
  }
}

/// One session of a participant served across a connection
/// ([ServeParticipant.serve], SPEC §14, §22.4): the registry as the
/// participant may see and use it; and, in its [vocabularies] and as far as
/// [rights] let it, an owner of words of its own, whose commands it serves
/// over the same connection. It ends by itself when the connection does
/// (its transport ends), its words going; [dispose] ends it sooner, the
/// connection still up.
/// A participant served across a connection (`participant.serve`): who
/// it is, when it ended, and its end.
/// Frozen (`app.dart`); only the library makes one.
abstract interface class IRemoteSession {
  /// Who the part across speaks as.
  Principal get who;

  /// Completes when the session ended: closed, taken over by a new one, or
  /// its connection gone. Its words went with it.
  Future<void> get ended;

  /// Ends the session: its words go, its calls are refused.
  void dispose();
}

final class RemoteSession extends ParlanceContractPeer
    implements IRemoteSession {
  RemoteSession._(
    super.endpoint,
    LocalParticipant participant, {
    String? session,
    this.feedBacklog = 256,
    this.maxSubscription = 4096,
    this.limits = const SessionLimits(),
    LogScope? log,
    Set<String>? features,
  }) : features = features ?? parlanceFeatures,
       session = session ?? newId(),
       registry = registryOf(participant),
       principal = participant.who,
       _owner = ParlanceOwnerContractPeerCaller(endpoint),
       _p = participant {
    this.log = (log ?? registry.log.child('sessions')).withData({
      'session': this.session,
      'principal': principal.selector,
    });
    if (this.log.isEnabled(RpcLogLevel.info)) this.log.info('session opened');
    _renames = registry.catalogChanges.listen((c) {
      if (c is AliasChanged || c is DescriptorAdded || c is DescriptorRemoved) {
        if (_askedStates != null || _askedFacts != null) _carry(_subscription);
      }
    });
    // The connection lost, its transport ends (rpc_dart closes it then):
    // the session ends with it, nothing closing it by hand.
    _gone = endpoint.transport.incomingMessages.listen(
      (_) {},
      onDone: _connectionGone,
      onError: (Object _) => _connectionGone(),
      cancelOnError: true,
    );
  }

  StreamSubscription<Object?>? _gone;

  void _connectionGone() {
    if (_closed) return;
    if (log.isEnabled(RpcLogLevel.info)) log.info('connection gone');
    dispose();
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

  /// How much the part across may hold here (SPEC §14): what it asks past
  /// them is refused, the rest it holds staying.
  final SessionLimits limits;

  /// The bytes of each value it holds, by state and key, and their sum.
  final Map<String, Map<String?, int>> _bytes = {};
  int _bytesHeld = 0;

  /// Its calls the registry has not answered yet.
  int _calling = 0;

  /// What it asks past [limits], refused.
  static Never _exhausted(String why) =>
      throw RpcStatusException(RpcStatus.resourceExhausted, why);

  /// What of the protocol it tells the part across it speaks (SPEC §14):
  /// every feature of this build unless given; fewer stand in, in a test,
  /// for a host built against an older parlance.
  final Set<String> features;

  /// Who the session acts for; fixed when the host accepted the connection.
  final Principal principal;
  final String session;

  /// The session as a participant in this process: what it defines, writes
  /// and says goes through it, in its vocabularies and with its rights.
  final LocalParticipant _p;

  Set<String> get vocabularies => _p.vocabularyNames;
  ParticipantRights get rights => _p.rights;

  /// The participant's side, serving the session's commands.
  final ParlanceOwnerContractPeerCaller _owner;

  final Map<String, IStateHandle> _states = {};
  final Map<String, IFactHandle> _facts = {};
  final Map<String, IHandle> _commands = {};

  /// Why each of its commands cannot run now, as the participant told.
  final Map<String, String> _unavailable = {};

  /// The choices it gives, as it sent them last.
  final Map<
    String,
    ({IHandle handle, List<Choice> list, LocalParticipant speaker})
  >
  _choices = {};

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
        return f.cause.child(f.id, by: who, word: f.fact);
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
    // A copy that settles waits to reach the seq told here: its feeds are
    // told the ticks they were not sent went by, as after a call.
    final seq = registry.seq;
    if (seq > _owed) _owed = seq;
    for (final f in [..._feeds]) {
      if (f.listened) f.catchUp(seq);
    }
    // What this session may call: so its clients offer only that.
    return WireDescription({
      ...registry.describeFor(principal),
      'protocol': parlanceProtocol,
      'features': [...features],
      'principal': principal.toJson(),
      'vocabularies': [..._p.vocabularyNames],
      // Who may read and call its words by default, as the host said: the
      // part across fills its words' descriptors so.
      'defaults': {
        'read': ?_p.access.readers?.toJson(),
        'call': ?_p.access.callers?.toJson(),
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

  /// The feeds open now; a feed gets items and catch-ups once listened to.
  final Set<_Feed> _feeds = {};

  /// The highest seq a call of the session answered at: what its mirror
  /// waits to reach before the call returns there.
  int _owed = 0;

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
    final feed = _Feed(this, request);
    _feeds.add(feed);
    return feed.out.stream;
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
    _askedStates = request.states?.toSet();
    _askedFacts = request.facts?.toSet();
    final n = ++_subscription;
    _carry(n, told: true);
    return WireJson({
      'subscription': n,
      // What it asked for and may not read: left out.
      'left': [
        for (final name in [...?request.states, ...?request.facts])
          if (!_reads(name)) name,
      ],
    });
  }

  /// What the session subscribed to, by the names it gave: what its feeds
  /// carry follows what they stand for as the catalog changes, so an old
  /// name of a word renamed while it follows it goes on reaching the word
  /// (SPEC §6.4). Null: everything.
  Set<String>? _askedStates;
  Set<String>? _askedFacts;
  StreamSubscription<CatalogChange>? _renames;

  /// Sets what the feeds carry from the names subscribed to, as the
  /// catalog has them now, and sends the values of the states they carry
  /// now and did not. [told]: for a subscription, which says its number
  /// even when nothing changed; else only a change is sent.
  void _carry(int subscription, {bool told = false}) {
    // A word it may not read is left out, not the whole subscription: one
    // such word among what its listeners ask for would otherwise hold back
    // every word added after it. Its status tells the participant why.
    final states = _askedStates?.where(_reads).toSet();
    final facts = _askedFacts?.where(_reads).toSet();
    _listenTo({...?states, ...?facts});
    final before = _stateFilter;
    // An old name of a word subscribes to the word (SPEC §6.4).
    final now = states?.map(registry.canonical).toSet();
    final heard = facts?.map(registry.canonical).toSet();
    final same = _sameSet(before, now) && _sameSet(_factFilter, heard);
    _stateFilter = now;
    _factFilter = heard;
    if (!told && same) return;
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
      'subscription': subscription,
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
      if (f.listened) f.send(item);
    }
  }

  static bool _sameSet(Set<String>? a, Set<String>? b) => a == null
      ? b == null
      : b != null && a.length == b.length && a.containsAll(b);

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
    // The session for one of its owners calls as that owner (SPEC §22.3).
    final by = _speakerOf(request.as).who;
    if (limits.calls case final max? when _calling >= max) {
      // Nothing ran: it may call again once one of its calls is answered.
      return WireCallReply(
        CallRefused(
          Refusal.unavailable,
          'the session has $max calls not answered yet, as many as it may',
        ).toJson(),
        epoch: registry.epoch,
        seq: registry.seq,
      );
    }
    _calling++;
    final CallResult<Object?> result;
    try {
      result = await registry.call(
        request.command,
        request.params,
        by: by,
        id: '${principal.selector}#${request.id}',
        cause: _cause(parent: request.parent, by: by),
      );
    } finally {
      _calling--;
    }
    final seq = registry.seq;
    if (seq > _owed) _owed = seq;
    for (final f in [..._feeds]) {
      if (f.listened) f.catchUp(seq);
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
          request.count.clamp(0, registry.limits.recentPerFact),
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
      _say(
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

  /// The session's participant for the owner [as] names (SPEC §22.3); the
  /// session itself for none. Anything but an owner of its principal is
  /// refused.
  LocalParticipant _speakerOf(Object? as) {
    if (as == null) return _p;
    final who = _principal(as);
    if (who == principal) return _p;
    if (who.owner.isEmpty || who.parent != principal) {
      _deny('$who is no owner of $principal');
    }
    return _p.ofOwner(who.owner);
  }

  Map<String, Object?> _op(Map<String, Object?> m) {
    final speaker = _speakerOf(m['as']);
    switch (m['op']) {
      case 'define':
        _define(_descriptor(_obj(m['descriptor'])), speaker);
      case 'undefine':
        _undefine(m['name']! as String);
      case 'set' || 'remove':
        _write(
          m['state']! as String,
          key: m['key'] as String?,
          value: m['value'],
          remove: m['op'] == 'remove',
          parent: m['parent'] as String?,
          speaker: speaker,
        );
      case 'emit':
        return {
          'taken': _say(
            m['fact']! as String,
            m['payload'],
            id: m['id'] as String?,
            by: m['by'] == null ? null : _principal(m['by']),
            parent: m['parent'] as String?,
            speaker: speaker,
          ),
        };
      case 'available':
        _available(m['command']! as String, m['why'] as String?);
      case 'kind':
        _choicesOf(
          m['name']! as String,
          m['entities'] as List? ?? const [],
          speaker,
        );
      case 'unkind':
        _choices.remove(m['name'])?.handle.dispose();
      case 'guard':
        _guard(m['id']! as String, speaker: speaker);
      case 'unguard':
        _guards.remove(speaker.guardId('${m['id']}'))?.dispose();
      case 'built':
        // Told by fingerprint first (SPEC §25.4): the schemas it knows it
        // takes as told, and answers which it does not.
        final schemas = {..._obj(m['words'])};
        final unknown = <String>[];
        for (final MapEntry(key: word, value: print) in _obj(
          m['prints'],
        ).entries) {
          if (registry.knownSchema('$print') case final schema?) {
            schemas[word] = schema;
          } else {
            unknown.add(word);
          }
        }
        builtAgainstSchemas(speaker, schemas, from: m['from'] as String?);
        if (unknown.isNotEmpty) return {'unknown': unknown};
      case 'unbuilt':
        forgetBuiltAgainst(speaker);
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

  void _define(Descriptor d, [LocalParticipant? speaker]) {
    final p = speaker ?? _p;
    final words = _states.length + _facts.length + _commands.length;
    if (limits.words case final max? when words >= max) {
      _exhausted('the session defines $max words, as many as it may');
    }
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
    for (final b in (_bytes.remove(name) ?? const {}).values) {
      _bytesHeld -= b;
    }
    h.dispose();
  }

  void _write(
    String state, {
    String? key,
    Object? value,
    bool remove = false,
    String? parent,
    LocalParticipant? speaker,
  }) {
    final w = _states[state];
    if (w == null) {
      if (registry.stateDescriptor(state) == null) {
        throw RpcStatusException(RpcStatus.notFound, 'no state $state');
      }
      _deny('$state is not the session\'s own');
    }
    final cause = _cause(parent: parent, by: (speaker ?? _p).who);
    final had = _bytes[state]?[key] ?? 0;
    final weight = remove ? 0 : jsonWeight(value) + (key?.length ?? 0);
    if (limits.stateBytes case final max?
        when weight > had && _bytesHeld - had + weight > max) {
      _exhausted(
        'the session holds at most $max bytes of values: $state'
        '${key == null ? '' : '[$key]'} would make it '
        '${_bytesHeld - had + weight}',
      );
    }
    try {
      remove
          ? w.remove(key: key, cause: cause)
          : w.set(value, key: key, cause: cause);
      _bytesHeld += weight - had;
      if (remove) {
        _bytes[state]?.remove(key);
      } else {
        (_bytes[state] ??= {})[key] = weight;
      }
    } on TypeMismatch catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '$e');
    } on ArgumentError catch (e) {
      throw RpcStatusException(RpcStatus.invalidArgument, '${e.message}');
    }
  }

  bool _say(
    String fact,
    Object? payload, {
    String? id,
    Principal? by,
    String? parent,
    LocalParticipant? speaker,
  }) {
    final p = speaker ?? _p;
    final sayer = _facts[fact];
    if (sayer == null) {
      if (registry.factDescriptor(fact) == null) {
        throw RpcStatusException(RpcStatus.notFound, 'no fact $fact');
      }
      // A fact has one owner (SPEC §6): another's is not said here.
      _deny('$fact is not the session\'s own');
    }
    try {
      return _permitted(
        () => sayer.say(
          payload,
          id: id == null ? null : '${principal.selector}#$id',
          cause: _cause(parent: parent, by: by ?? p.who),
        ),
      );
    } on TypeMismatch catch (x) {
      throw RpcStatusException(RpcStatus.invalidArgument, '$x');
    } on StateError catch (x) {
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

  /// The choices of [name], as the wire says them ([entities]).
  void _choicesOf(
    String name,
    List<Object?> entities, [
    LocalParticipant? speaker,
  ]) {
    if (limits.choices case final max?) {
      final others = [
        for (final MapEntry(:key, :value) in _choices.entries)
          if (key != name) value.list.length,
      ].fold(0, (a, b) => a + b);
      if (others + entities.length > max) {
        _exhausted(
          'the session has at most $max choices: $name would '
          'make it ${others + entities.length}',
        );
      }
    }
    final list = [
      for (final e in entities.cast<Map<Object?, Object?>>())
        Choice(
          e['id']! as String,
          label: e['label'] as String?,
          meta: _obj(e['meta']),
        ),
    ];
    if (_choices[name] case final c?) {
      _choices[name] = (handle: c.handle, list: list, speaker: c.speaker);
      _permitted(() => c.speaker.choicesChanged(name));
      return;
    }
    final p = speaker ?? _p;
    try {
      final handle = p.addChoices(
        Choices(name, list: () => _choices[name]?.list ?? const []),
      );
      _choices[name] = (handle: handle, list: list, speaker: p);
    } on StateError catch (e) {
      throw RpcStatusException(RpcStatus.alreadyExists, e.message);
    }
  }

  /// A guard of the session's or one of its owners', on its commands only, asked in
  /// its turn: the participant judges the call. Known as `<speaker>/<id>`.
  void _guard(String id, {LocalParticipant? speaker}) {
    final p = speaker ?? _p;
    final full = p.guardId(id);
    if (limits.guards case final max?
        when _guards.length >= max && !_guards.containsKey(full)) {
      // Each guard is asked of every call there is: a few, not many.
      _exhausted('the session has $max guards, as many as it may');
    }
    try {
      _guards[full] = p.addAskedGuard(id, (c) async {
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
      });
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

  /// A new session of its principal took its place: this one's connection
  /// is gone, though not seen to (SPEC §14).
  void _takenOver() {
    if (log.isEnabled(RpcLogLevel.info)) {
      log.info('taken over by a new session');
    }
    dispose();
  }

  @override
  Principal get who => principal;

  final Completer<void> _ended = Completer();

  @override
  Future<void> get ended => _ended.future;

  /// Ends the session: its words go, its calls are refused.
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _ended.complete();
    if (log.isEnabled(RpcLogLevel.info)) log.info('session closed');
    unawaited(_catalogUse?.cancel());
    unawaited(_renames?.cancel());
    unawaited(_gone?.cancel());
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
    _choices.clear();
    _guards.clear();
    _unavailable.clear();
    _listenTo(const {});
    _p.dispose();
    // Its feeds end: nothing more goes to a session that ended.
    for (final f in [..._feeds]) {
      unawaited(f.end());
    }
    _feeds.clear();
  }
}

/// Why a remote owner's command failed, in its words.
final class _Failed implements Exception {
  const _Failed(this.why);
  final String why;

  @override
  String toString() => why;
}

/// How much a session lets the part across it hold of the host's (SPEC
/// §14): it may be code of another's, or code with a defect, and the host
/// is the one that keeps what it asks. Each bound is on by default, wide
/// for a part that works and narrow for one that runs away; null takes
/// it off ([unbounded], for a part as trusted as the host's own code).
final class SessionLimits {
  const SessionLimits({
    this.stateBytes = 1 << 20,
    this.words = 256,
    this.guards = 16,
    this.choices = 1000,
    this.calls = 16,
  });

  /// No bounds.
  static const unbounded = SessionLimits(
    stateBytes: null,
    words: null,
    guards: null,
    choices: null,
    calls: null,
  );

  /// About how many bytes the values it writes take together, as JSON,
  /// every key of every state of its: a keyed state it never empties
  /// stops here.
  final int? stateBytes;

  /// How many words it defines: states, facts, commands and queries.
  final int? words;

  /// How many guards it adds: each is asked of every call there is.
  final int? guards;

  /// How many entities its kinds have together: they go in the catalog
  /// every session gets.
  final int? choices;

  /// How many of its calls wait for an answer at once; one past them is
  /// refused (`unavailable`) and runs nowhere.
  final int? calls;
}
