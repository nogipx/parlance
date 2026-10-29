import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:clock/clock.dart' as clock_zone;
import 'package:clock/clock.dart' show Clock;
import 'package:rpc_dart/rpc_dart.dart';

import '../participant/owner.dart';
import '../participant/participant.dart';
import '../participant/serving.dart';
import '../registry/cause.dart';
import '../registry/compat.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/json.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/shapes.dart';
import '../registry/types.dart';
import '../registry/words.dart';
import '../view/mirror_view.dart';
import '../view/view.dart' show wordStatusChanges;
import 'built.dart';
import 'contract.dart';
import 'client.dart';
import 'mirror.dart';

part 'participant_errors.dart';
part 'participant_words.dart';
part 'participant_part.dart';

/// A participant across a connection (SPEC §22.4): the same
/// [IParticipant] a part has in the host's process, over its session.
///
/// What it asks the registry (defining, writing, saying, its kinds, its
/// guards, its commands' availability) goes in its order, what it asks in
/// one turn of its event loop as one tick; the handle comes back at once,
/// and a refusal comes after, to [errors]. It reads its own states as it
/// wrote them, and another's as its mirror has them: those it watches, or
/// listens to the changes of.
///
/// It joins over an [RpcClientConnection] ([join]) and outlives a lost
/// connection: the host's new session gets everything it has defined as
/// it stands now, in one tick, and then what it said meanwhile. A
/// connection that does not come back (a wasm module's to its host, one in
/// memory) is one whose factory gives the same transport and that does not
/// reconnect (`shouldReconnect: (_) => false`).
final class RemoteParticipant implements IParticipant {
  RemoteParticipant._(
    this.endpoint,
    this._client,
    this._mirror,
    this.who,
    this.vocabularies,
    this.access,
    this._onError,
    this.log,
    this.keepAway,
  ) : _view = MirrorView(_mirror, _client),
      _callLog = log.child('calls');

  /// Where it logs: how its connection goes, what the host refused, and a
  /// span for each call it serves, in the host's trace; `LogScope.noop`
  /// unless given.
  final LogScope log;
  final LogScope _callLog;

  /// How many facts said while away it keeps to send when back; past it
  /// the oldest go, and how many is told to [errors] once it is back.
  final int keepAway;
  int _droppedAway = 0;

  /// Its access by default, the host's: as the participant the host
  /// serves was made (SPEC §22.2), told when it joins.
  @override
  final WordAccess access;

  /// Joins the registry over [connection], starting it when it is idle:
  /// the participant makes its peer endpoint on the connection's transport
  /// ([endpoint], for other contracts on the same connection), waits until
  /// it is online, and joins again each time it is back. Its principal and
  /// vocabularies are the session's the host made. [interceptors] go on that
  /// endpoint before its first call (an OTel pair, say); on a peer endpoint
  /// they see the calls it makes and those it serves.
  ///
  /// [requires]: the features of the protocol it cannot do without (SPEC
  /// §14); a host that does not speak one is refused
  /// ([ProtocolMismatch]), on joining and on joining again.
  static Future<RemoteParticipant> join(
    RpcClientConnection connection, {
    void Function(ParticipantError error)? onError,
    LogScope? log,
    int keepAway = 1000,
    Iterable<IRpcInterceptor> interceptors = const [],
    Set<String> requires = const {},
  }) async {
    final endpoint = RpcPeerEndpoint(transport: connection.transport);
    interceptors.forEach(endpoint.addInterceptor);
    endpoint.start();
    final online = connection.currentState is RpcClientOnline
        ? null
        : connection.state.firstWhere(
            (s) => s is RpcClientOnline || s is RpcClientDisconnected,
          );
    if (connection.currentState is RpcClientIdle) connection.connect();
    if (await online case RpcClientDisconnected(:final reason)) {
      await endpoint.close();
      throw StateError('the connection gave up: $reason');
    }
    final RemoteParticipant p;
    try {
      p = await _start(endpoint, onError, log, keepAway, requires);
    } on Object {
      await endpoint.close();
      rethrow;
    }
    p._joined = connection;
    p._connection = connection.state.listen(p._onConnection);
    return p;
  }

  /// Joins the registry over [endpoint], one made elsewhere that does not
  /// come back once lost (a guest's in a wasm or JavaScript runtime): the
  /// same participant, but with no connection to join again over. The
  /// endpoint stays the caller's: [close] does not close it.
  static Future<RemoteParticipant> over(
    RpcPeerEndpoint endpoint, {
    void Function(ParticipantError error)? onError,
    LogScope? log,
    int keepAway = 1000,
    Set<String> requires = const {},
  }) async {
    final p = await _start(endpoint, onError, log, keepAway, requires);
    p._ownsEndpoint = false;
    return p;
  }

  static Future<RemoteParticipant> _start(
    RpcPeerEndpoint endpoint,
    void Function(ParticipantError error)? onError,
    LogScope? log,
    int keepAway,
    Set<String> requires,
  ) async {
    final client = ParlanceClient(endpoint);
    final d = await client.describe();
    final speaks = checkProtocol(
      d['protocol'],
      features: d['features'],
      requires: requires,
    );
    final p = RemoteParticipant._(
      endpoint,
      client,
      RegistryMirror(),
      Principal.fromJson(d['principal']),
      {...(d['vocabularies'] as List? ?? const []).cast<String>()},
      _accessOf(d['defaults']),
      onError,
      log ?? LogScope.noop,
      keepAway,
    );
    p
      ..requires = requires
      .._speaks = speaks;
    if (p.log.isEnabled(RpcLogLevel.info)) {
      p.log.info('joined', data: {'as': p.who.selector});
    }
    endpoint.registerServiceContract(_Served(endpoint, p));
    // It keeps of another's only what it watches: nothing to start with.
    unawaited(p._mirror.subscribe(states: const {}, facts: const {}));
    // What its listeners ask for, past what a session carries for one:
    // told, and everything carried rather than some of it missing.
    p._mirror.onRefused = (e) => p._fail(
      const {'op': 'subscribe'},
      'resourceExhausted',
      'its listeners ask for more than a session carries by name, so it '
          'carries everything: $e',
    );
    // What the host's feed brought and is no item: followed again, told.
    p._mirror.onMalformed = (e, {required gaveUp}) => p._fail(
      const {'op': 'feed'},
      'malformed',
      gaveUp
          ? 'the host keeps sending what cannot be read, so it stopped '
                'following the feed until it joins again: $e'
          : 'the host sent what cannot be read; following again from now: $e',
    );
    p._mirror.follow(client);
    p._changes = p._mirror.changes.listen((_) => p._checkAvailability());
    // It has joined when its view is live: the feed's first snapshot came.
    if (!p._mirror.synced) {
      await p._mirror.changes
          .firstWhere((_) => p._mirror.synced)
          .timeout(const Duration(seconds: 10), onTimeout: () {});
    }
    return p;
  }

  /// Its access by default, as the host served it (SPEC §22.2).
  static WordAccess _accessOf(Object? json) {
    final m = json is Map ? json : const <String, Object?>{};
    return WordAccess(
      read: m['read'] == null ? null : Callers.fromJson(m['read']),
      call: m['call'] == null ? null : Callers.fromJson(m['call']),
    );
  }

  /// Whether [close] closes [endpoint]: its own, made on a connection.
  bool _ownsEndpoint = true;

  StreamSubscription<RpcClientConnectionState>? _connection;

  /// The connection it joined over; null for one given an endpoint.
  RpcClientConnection? _joined;

  /// Asks to join again while the connection is up but joining failed.
  Timer? _retry;
  Duration _retryAfter = _firstRetry;
  static const _firstRetry = Duration(milliseconds: 250);
  static const _lastRetry = Duration(seconds: 30);

  /// Whether its session is there to ask: false from a drop until it has
  /// joined the host's new session.
  bool _online = true;
  bool _rejoining = false;

  void _onConnection(RpcClientConnectionState s) {
    switch (s) {
      case RpcClientOnline():
        if (!_online) unawaited(_rejoin());
      case RpcClientOffline() || RpcClientConnecting():
        if (_online && log.isEnabled(RpcLogLevel.info)) log.info('offline');
        _online = false;
      case RpcClientDisconnected(:final reason):
        // The connection gave up: nothing it asks reaches the registry.
        _online = false;
        _fail(const {'op': 'join'}, 'lost', 'the connection gave up: $reason');
      default:
    }
  }

  /// Joins the host's new session: what it has defined, as it stands now,
  /// as one tick; then what it said while away.
  Future<void> _rejoin() async {
    if (_rejoining || _disposed) return;
    _rejoining = true;
    try {
      final d = await _client.describe();
      try {
        _speaks = checkProtocol(
          d['protocol'],
          features: d['features'],
          requires: requires,
        );
      } on ProtocolMismatch catch (e) {
        // A host behind the one it joined: it stays away, and says why.
        _fail(const {'op': 'rejoin'}, 'protocol', '$e');
        return;
      }
      final now = Principal.fromJson(d['principal']);
      if (now != who) {
        _fail(
          const {'op': 'rejoin'},
          'permissionDenied',
          'the new session is $now\'s, not $who\'s',
        );
        return;
      }
      // What it has as it stands, then what it said while away, in order.
      _queue
        ..insertAll(0, _standing())
        ..addAll(_away);
      _away.clear();
      for (final c in _commands.values) {
        c.told = false;
      }
      _online = true;
      if (log.isEnabled(RpcLogLevel.info)) log.info('joined again');
      if (_droppedAway > 0) {
        _fail(
          const {'op': 'emit'},
          'dropped',
          '$_droppedAway facts said while away were dropped, past the '
              '$keepAway kept',
        );
        _droppedAway = 0;
      }
      _mirror.follow(_client);
      _checkAvailability();
      _retryAfter = _firstRetry;
      await flush();
    } on Object {
      // Dropped again before it joined: the next time it is online, or,
      // while the connection says it is, after a while.
      _online = false;
      _rejoinLater();
    } finally {
      _rejoining = false;
    }
  }

  /// Joins again after a while, each time later, while the connection is
  /// up and the session is not: no state of the connection will change to
  /// say so.
  void _rejoinLater() {
    if (_disposed || _retry != null || _joined == null) return;
    _retry = Timer(_retryAfter, () {
      _retry = null;
      if (_disposed || _online) return;
      if (_joined?.currentState is! RpcClientOnline) return;
      unawaited(_rejoin());
    });
    final next = _retryAfter * 2;
    _retryAfter = next > _lastRetry ? _lastRetry : next;
  }

  /// What it has defined, as it stands now, in the order a session takes
  /// it: kinds before the values that name their entities, states before
  /// the commands that set them.
  List<Map<String, Object?>> _standing() => [
    for (final k in _kinds.values) _kindOp(k.kind, k.as),
    for (final s in _states.values)
      {'op': 'define', 'descriptor': s.d.toJson(), ..._asOf(s.as)},
    for (final f in _facts.values)
      {'op': 'define', 'descriptor': f.d.toJson(), ..._asOf(f.as)},
    for (final c in _commands.values)
      {'op': 'define', 'descriptor': c.d.toJson(), ..._asOf(c.as)},
    for (final MapEntry(key: state, value: values) in _own.entries)
      for (final MapEntry(:key, :value) in values.entries)
        {
          'op': 'set',
          'state': state,
          'key': ?key,
          'value': value,
          ..._asOf(_states[state]?.as),
        },
    for (final g in _guards.values)
      {'op': 'guard', 'id': g.id, 'overridable': g.overridable, ..._asOf(g.as)},
    if (_speaks.contains('built')) ..._built.standing(),
  ];

  /// The peer endpoint it made on its connection.
  final RpcPeerEndpoint endpoint;
  final ParlanceClient _client;
  final RegistryMirror _mirror;
  final MirrorView _view;
  final void Function(ParticipantError error)? _onError;
  StreamSubscription<void>? _changes;

  @override
  final Principal who;

  @override
  final Set<String> vocabularies;

  // Told as each answer comes, so a refusal is heard before the flush it
  // came in completes.
  final StreamController<ParticipantError> _errors = StreamController.broadcast(
    sync: true,
  );

  /// What the registry refused of what it asked: told before the [flush]
  /// that brought the refusal completes.
  Stream<ParticipantError> get errors => _errors.stream;

  /// Its own states, as it wrote them: name, key, value.
  final Map<String, Map<String?, Object?>> _own = {};

  /// Its own states and facts, as defined, and which part defined each
  /// (`as`, null for itself): what a new session is given.
  final Map<String, ({StateDescriptor d, Principal? as})> _states = {};
  final Map<String, ({FactDescriptor d, Principal? as})> _facts = {};
  final Map<String, _Command> _commands = {};

  /// Its guards and its parts', by the id the host knows them by.
  final Map<
    String,
    ({String id, GuardCheck check, bool overridable, Principal? as})
  >
  _guards = {};
  final Map<String, ({EntityKind kind, Principal? as})> _kinds = {};

  final Map<Principal, _Part> _parts = {};
  bool _disposed = false;

  static Map<String, Object?> _asOf(Principal? as) => {'as': ?as?.toJson()};

  @override
  Clock get clock => clock_zone.clock;

  void _live() {
    if (_disposed) throw StateError('participant $who is gone');
  }

  bool _owns(String name) =>
      vocabularies.any((ns) => name == ns || name.startsWith('$ns.'));

  void _mayDefine(Descriptor d) {
    _live();
    if (!_owns(d.name)) {
      throw NotPermitted(
        '$who defines in ${vocabularies.isEmpty ? 'no vocabulary' : vocabularies.join(', ')}, not ${d.name}',
      );
    }
    // A name it holds is taken, as in the host's process: defined again,
    // it would take the place of its own word here while the host keeps
    // the first.
    if (_states.containsKey(d.name) ||
        _facts.containsKey(d.name) ||
        _commands.containsKey(d.name)) {
      throw StateError('${d.name} is defined');
    }
    if (_mirror.canonical(d.name) case final now when now != d.name) {
      throw StateError('${d.name} is an old name of $now');
    }
  }

  /// Whether a cause by [by] is [speaker]'s own act: [speaker] itself, or
  /// a whole it is part of, up to this participant.
  bool _ownAct(Principal by, Principal speaker) =>
      by == speaker || (speaker.isWithin(by) && by.isWithin(who));

  Cause? _as(Cause? cause, [Principal? speaker]) {
    final s = speaker ?? who;
    // In a handler, what it does follows from the call it serves.
    if (cause == null) return inReplyAs(s);
    if (!_ownAct(cause.by, s)) {
      throw NotPermitted('$s acts as itself, not as ${cause.by}');
    }
    return cause;
  }

  // --- What it asks, in order ---------------------------------------------

  final List<Map<String, Object?>> _queue = [];
  Future<void>? _sending;

  /// What the send under way carries.
  List<Map<String, Object?>> _sent = const [];
  bool _scheduled = false;

  void _ask(Map<String, Object?> op) {
    _live();
    // What a query's handler tries to change is refused here, as in the
    // host's process (SPEC §6.2).
    if (op['op'] case 'set' || 'remove' || 'emit') {
      refuseInQuery('${op['op']} ${op['state'] ?? op['fact']}');
    }
    // Away, only what it says waits: the rest a new session gets as it
    // stands then.
    if (!_online) {
      if (op['op'] == 'emit') _keepAway(op);
      return;
    }
    _queue.add(op);
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      // What it wrote may change what its commands say of themselves:
      // told in the same tick.
      _checkAvailability();
      unawaited(flush());
    });
  }

  /// The facts said while away, oldest first, to send when back.
  final ListQueue<Map<String, Object?>> _away = ListQueue();

  /// Keeps [op], a fact said while away: past [keepAway], the oldest goes.
  void _keepAway(Map<String, Object?> op) {
    if (_away.length >= keepAway) {
      _away.removeFirst();
      _droppedAway++;
    }
    _away.add(op);
  }

  /// Completes when the registry has answered all it asked so far: what
  /// it asks after the call is not waited for, so a flush ends however
  /// much is written meanwhile.
  Future<void> flush() async {
    final asked = Set<Map<String, Object?>>.identity()
      ..addAll(_queue)
      ..addAll(_sent);
    _flushing.add(asked);
    try {
      await _flushAsked(asked);
    } finally {
      _flushing.remove(asked);
    }
  }

  /// What each flush under way waits for: an op the host's answer to one
  /// of them adds is waited for as part of it.
  final List<Set<Map<String, Object?>>> _flushing = [];

  Future<void> _flushAsked(Set<Map<String, Object?>> asked) async {
    while (true) {
      // Done once nothing it asked waits or goes: a send of what came
      // after is not waited for.
      if (!_queue.any(asked.contains) && !_sent.any(asked.contains)) return;
      if (_sending case final s?) {
        await s;
        continue;
      }
      if (!_online) return;
      final ops = [..._queue];
      _queue.clear();
      final done = Completer<void>();
      _sending = done.future;
      _sent = ops;
      try {
        final results = await _client.apply(ops);
        for (var i = 0; i < ops.length && i < results.length; i++) {
          if (results[i]['error'] case final String code) {
            _fail(ops[i], code, '${results[i]['message']}');
          } else if (_built.answered(ops[i], results[i]) case final op?) {
            // The schemas the host does not know by their fingerprints.
            _queue.add(op);
            for (final asked in _flushing) {
              if (asked.contains(ops[i])) asked.add(op);
            }
          }
        }
      } on Object catch (e) {
        if (e is RpcStatusException && answeredBySession(e.statusCode)) {
          // The session answered, failing all of it: each op is told so,
          // and the session is still there for what comes next.
          for (final op in ops) {
            _fail(op, e.statusCode.name, e.message);
          }
        } else if (!_disposed) {
          // The connection dropped: a new session gets what it defined as
          // it stands; what it said goes again after, its ids letting the
          // registry drop one it took. What it asked besides is in what it
          // has as it stands.
          _online = false;
          _rejoinLater();
          final said = [
            for (final op in [...ops, ..._queue])
              if (op['op'] == 'emit') op,
            ..._away,
          ];
          _queue.clear();
          _away.clear();
          said.forEach(_keepAway);
        } else {
          for (final op in ops) {
            _fail(op, 'lost', '$e');
          }
        }
      } finally {
        _sending = null;
        _sent = const [];
        done.complete();
      }
    }
  }

  void _fail(Map<String, Object?> op, String code, String message) {
    final e = ParticipantError(op, code, message);
    if (log.isEnabled(RpcLogLevel.warning)) {
      log.warning(
        'refused by the host',
        data: {'op': '${op['op']}', 'code': code, 'message': message},
      );
    }
    _onError?.call(e);
    if (!_errors.isClosed) _errors.add(e);
  }

  static Map<String, Object?> _causeOf(Cause? cause) => {
    'parent': ?cause?.parent,
  };

  // --- Reading and calling, as [who] --------------------------------------

  @override
  Object? read(String state, {String? key}) =>
      _own.containsKey(state) ? _own[state]![key] : _view.read(state, key: key);

  /// Across a connection a value is JSON: decoded, once a value.
  @override
  T? readAs<T>(String state, Shape<T> shape, {String? key}) =>
      decodeKnown(shape, read(state, key: key), (e) => _unknown(state, e));

  @override
  Map<String?, Object?> readAll(String state) => _own.containsKey(state)
      ? Map.unmodifiable(_own[state]!)
      : _view.readAll(state);

  @override
  Future<Map<String?, Object?>> fetch(String state, {bool keep = true}) async =>
      _own.containsKey(state) ? readAll(state) : _view.fetch(state, keep: keep);

  @override
  Future<Map<String, Object?>> describe() {
    _live();
    return _asked(_client.describe);
  }

  /// [ask] of the host, its failures told as a participant's in this
  /// process would be: a refusal as [NotPermitted] (or [denied]), [missing]
  /// for a word there is not, and no host to ask as [RegistryUnreachable].
  /// The wire's errors stay the package's.
  Future<T> _asked<T>(
    Future<T> Function() ask, {
    T Function()? missing,
    T Function()? denied,
  }) async {
    try {
      return await ask();
    } on RpcStatusException catch (e) {
      if (e.statusCode == RpcStatus.permissionDenied) {
        if (denied != null) return denied();
        throw NotPermitted(e.message);
      }
      if (e.statusCode == RpcStatus.notFound && missing != null) {
        return missing();
      }
      throw RegistryUnreachable(e.message);
    } on NotPermitted {
      rethrow;
    } on Object catch (e) {
      throw RegistryUnreachable('$e');
    }
  }

  @override
  Future<Explanation> explain(String state, {String? key}) async {
    _live();
    // A state there is not explains itself as nothing, as in the host's
    // process: no value, no change.
    return _asked(
      () => _client.why(state, key: key),
      missing: () => Explanation(
        state: state,
        key: key,
        value: null,
        change: null,
        trail: const [],
      ),
    );
  }

  @override
  Stream<void> get catalogChanges => _mirror.catalogChanges;

  /// The catalog as its feed last told it ([describe] asks the host anew):
  /// for a screen that draws labels and entities as they are now.
  Map<String, Object?> get catalog => _mirror.catalog;

  @override
  Stream<Object?> watch(String state, {String? key}) {
    late StreamController<Object?> out;
    StreamSubscription<void>? sub;
    Object? last;
    var told = false;
    // Another's value is told once the mirror has it: not null first for
    // not having it yet.
    var ready = _own.containsKey(state);
    void tell() {
      if (!ready || out.isClosed) return;
      final now = read(state, key: key);
      if (told && jsonEquals(now, last)) return;
      told = true;
      last = now;
      out.add(now);
    }

    out = StreamController<Object?>(
      onListen: () {
        sub = _view.changes({state}).listen((_) => tell());
        if (ready) {
          tell();
        } else {
          unawaited(
            _view.settled.then((_) {
              ready = true;
              tell();
            }),
          );
        }
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Stream<T?> watchAs<T>(String state, Shape<T> shape, {String? key}) => watch(
    state,
    key: key,
  ).map((v) => decodeKnown(shape, v, (e) => _unknown(state, e)));

  @override
  Stream<void> changes(Set<String> states) => _view.changes(states);

  @override
  Stream<FactMessage> facts(String fact) => _view.facts(fact);

  @override
  Stream<(T, FactMessage)> factsAs<T>(String fact, Shape<T> shape) =>
      facts(fact).expand((m) {
        try {
          return [(decodeWith(shape, m.payload) as T, m)];
        } on Object catch (e) {
          _unknown(fact, e);
          return const [];
        }
      });

  /// What it told of values its code could not read, by word and why.
  final Set<String> _unknownTold = {};

  /// [word] holds a value this build cannot read (SPEC §25.2): its typed
  /// read gave none, and that is told on [errors], once a word and why.
  void _unknown(String word, Object e) {
    if (_unknownTold.length >= 1024 || !_unknownTold.add('$word $e')) {
      return;
    }
    final error = ParticipantError(
      {'op': 'read', 'word': word},
      'unreadable',
      '$word: $e',
    );
    if (log.isEnabled(RpcLogLevel.warning)) {
      log.warning(
        'a value this build cannot read',
        data: {'word': word, 'why': '$e'},
      );
    }
    _onError?.call(error);
    if (!_errors.isClosed) _errors.add(error);
  }

  @override
  Future<List<FactMessage>> recent(String fact, int count) =>
      // As in the host's process: none of a fact there is not, or one it
      // may not hear.
      _asked(
        () => _view.recent(fact, count),
        missing: () => const [],
        denied: () => const [],
      );

  /// Calls [command] as [who], after what it asked before has been done.
  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
    bool override = false,
  }) => _call(command, params, id: id, cause: cause, override: override);

  /// Across a connection the params go as JSON.
  @override
  Future<CallResult<Object?>> callAs(
    String command,
    Object? params,
    Shape<Object?> shape, {
    String? id,
    Cause? cause,
    bool override = false,
  }) => call(
    command,
    shape.toJson(params)! as Map<String, Object?>,
    id: id,
    cause: cause,
    override: override,
  );

  Future<CallResult<Object?>> _call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
    Principal? as,
    bool override = false,
  }) async {
    _live();
    final c = _as(cause, as);
    // A query's handler may ask another query, never call a command.
    if (answeringQuery() != null && !_isQuery(command)) {
      refuseInQuery('call $command');
    }
    await flush();
    // What its listeners asked for reaches the host before the call, so
    // what the call writes comes back on the feed.
    if (_online) await _view.settled;
    final r = await _client.callAt(
      command,
      params,
      id: id,
      override: override,
      parent: c?.parent,
      as: as,
    );
    if ((r.epoch, r.seq) case (final epoch?, final seq?)) {
      await _mirror.reach(epoch, seq);
    }
    return r.result;
  }

  /// Whether [command] is a query, as the catalog says.
  bool _isQuery(String command) {
    final name = _mirror.canonical(command);
    for (final d in _mirror.catalog['descriptors'] as List? ?? const []) {
      if (d case {'name': final n, 'is': 'query'} when n == name) return true;
    }
    return false;
  }

  @override
  bool get synced => _mirror.synced;

  @override
  WordStatus status(String word) => _view.status(word);

  @override
  Stream<WordStatus> statusChanges(String word) => _view.statusChanges(word);

  @override
  Descriptor? descriptor(String word) => _view.descriptor(word);

  /// The host is told each word once, by fingerprint, and told again on a
  /// new session.
  @override
  void builtAgainst(Iterable<IWord> words, {String? from}) {
    _builtAgainst(schemasOf(words), from, null);
    _watchBuilt(words, from);
  }

  /// Each word it was built against, watched: when one is there otherwise
  /// than its code was built against (SPEC §6.9), that is told as its
  /// error (`mismatch`, `{op: built, word}`), every break, so a guest
  /// learns it with nothing written for it; and in development, with no
  /// log, in the developer log.
  final Map<String, StreamSubscription<WordStatus>> _watching = {};

  void _watchBuilt(Iterable<IWord> words, String? from) {
    if (_disposed) return;
    for (final w in words) {
      unawaited(_watching.remove(w.name)?.cancel());
      _watching[w.name] = wordStatusChanges(this, w).listen((s) {
        if (s case WordMismatch(:final breaks)) {
          final why =
              '${w.name}${from == null ? '' : ' of $from'} is not as built '
              'against: ${breaks.join('; ')}';
          _fail(
            {'op': 'built', 'word': w.name, 'from': ?from},
            'mismatch',
            why,
          );
          if (!log.isEnabled(RpcLogLevel.warning)) {
            assert(() {
              developer.log(
                '${who.selector}: $why',
                name: 'parlance',
                level: 900,
              );
              return true;
            }());
          }
        }
      });
    }
  }

  /// What it and its parts told the host they were built against: kept
  /// also for a host that does not speak it, to tell a new session that
  /// does.
  final BuiltTold _built = BuiltTold();

  /// The features of the protocol it cannot do without (SPEC §14).
  late final Set<String> requires;

  /// The features the host speaks, as it told them on joining.
  Set<String> _speaks = const {};

  void _builtAgainst(
    Map<String, Object?> schemas,
    String? from,
    Principal? as,
  ) {
    if (_disposed) return;
    final ops = _built.tell(schemas, from: from, as: as);
    if (_speaks.contains('built')) ops.forEach(_ask);
  }

  // --- Its own words ------------------------------------------------------

  @override
  /// Across a connection its values go as JSON: its handle takes JSON,
  /// whatever [shape].
  IStateHandle defineState(StateDescriptor d, {Shape<Object?>? shape}) =>
      _defineState(d, null);

  IStateHandle _defineState(StateDescriptor raw, Principal? as) {
    _mayDefine(raw);
    final d = access.state(raw);
    _ask({'op': 'define', 'descriptor': d.toJson(), ..._asOf(as)});
    _states[d.name] = (d: d, as: as);
    _own[d.name] = {};
    return _State(this, d, as);
  }

  @override
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) => _defineCommand(d, handler, available, null);

  @override
  IHandle defineQuery(
    QueryDescriptor d,
    CommandHandler handler, {
    Availability? available,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) => _defineCommand(d, handler, available, null);

  /// A command or a query of its own, or of [as], a part of it.
  IHandle _defineCommand(
    CallableDescriptor d,
    CommandHandler handler,
    Availability? available,
    Principal? as,
  ) {
    _mayDefine(d);
    _ask({'op': 'define', 'descriptor': d.toJson(), ..._asOf(as)});
    final c = _Command(d, serving(handler), available, as);
    _commands[d.name] = c;
    return Disposer(() {
      if (_commands[d.name] != c) return;
      _commands.remove(d.name);
      _ask({'op': 'undefine', 'name': d.name});
    });
  }

  @override
  IFactHandle defineFact(FactDescriptor d, {Shape<Object?>? shape}) =>
      _defineFact(d, null);

  IFactHandle _defineFact(FactDescriptor raw, Principal? as) {
    _mayDefine(raw);
    final d = access.fact(raw);
    _ask({'op': 'define', 'descriptor': d.toJson(), ..._asOf(as)});
    _facts[d.name] = (d: d, as: as);
    return _Fact(this, d, own: true, as: as);
  }

  /// Another producer of an open [fact]; the host's rights decide, and a
  /// refusal comes to [errors] with its first fact.
  @override
  IFactHandle producer(String fact, {Shape<Object?>? shape}) =>
      _producer(fact, null);

  IFactHandle _producer(String fact, Principal? as) {
    _live();
    // As in the host's process: a fact only its owner says is refused
    // here, as its copy of the catalog knows it. One it does not know yet
    // may be defined by now: the host says, on [errors].
    if (_mirror.descriptorOf(fact) case FactDescriptor(open: false)) {
      throw StateError('$fact is not open');
    }
    return _Fact(
      this,
      FactDescriptor(fact, type: const AnyType(), open: true),
      own: false,
      as: as,
    );
  }

  /// A guard on its own commands, asked by the host in its turn (§10); a
  /// call it is not asked about in time is denied there.
  @override
  IHandle addGuard(String id, GuardCheck check, {bool overridable = true}) =>
      _addGuard(id, check, overridable, null);

  IHandle _addGuard(
    String id,
    GuardCheck check,
    bool overridable,
    Principal? as,
  ) {
    _live();
    // The host knows it by its speaker and its id, as it registers it.
    final full = '${(as ?? who).selector}#$id';
    // Taken, as in the host's process: added again, it would take the
    // place of its own guard here while the host keeps the first.
    if (_guards.containsKey(full)) throw StateError('guard $id exists');
    _guards[full] = (id: id, check: check, overridable: overridable, as: as);
    _ask({'op': 'guard', 'id': id, 'overridable': overridable, ..._asOf(as)});
    return Disposer(() {
      if (_guards.remove(full) == null) return;
      _ask({'op': 'unguard', 'id': id, ..._asOf(as)});
    });
  }

  @override
  IHandle registerKind(EntityKind kind) => _registerKind(kind, null);

  IHandle _registerKind(EntityKind kind, Principal? as) {
    _live();
    if (_kinds.containsKey(kind.name)) {
      throw StateError('kind ${kind.name} exists');
    }
    _kinds[kind.name] = (kind: kind, as: as);
    _ask(_kindOp(kind, as));
    return Disposer(() {
      if (_kinds.remove(kind.name) == null) return;
      _ask({'op': 'unkind', 'name': kind.name, ..._asOf(as)});
    });
  }

  static Map<String, Object?> _kindOp(EntityKind kind, Principal? as) => {
    'op': 'kind',
    'name': kind.name,
    'entities': [for (final e in kind.list()) e.toJson()],
    ..._asOf(as),
  };

  @override
  void entitiesChanged(String kind) {
    final k = _kinds[kind];
    if (k == null) throw NotPermitted('$who registered no kind $kind');
    _ask(_kindOp(k.kind, k.as));
  }

  /// A part of it (SPEC §22.3): its words, writes, calls and facts go as
  /// the part's, and the host holds them to the part.
  @override
  IParticipant child(String name) => _partOf(who.child(name));

  _Part _partOf(Principal p) {
    _live();
    return _parts[p] ??= _Part(this, p);
  }

  /// Withdraws what [part] and its own parts defined and added.
  void _withdraw(Principal part) {
    bool mine(Principal? as) => as != null && as.isWithin(part);
    for (final e in [..._states.entries]) {
      if (!mine(e.value.as)) continue;
      _states.remove(e.key);
      _own.remove(e.key);
      _ask({'op': 'undefine', 'name': e.key});
    }
    for (final e in [..._facts.entries]) {
      if (!mine(e.value.as)) continue;
      _facts.remove(e.key);
      _ask({'op': 'undefine', 'name': e.key});
    }
    for (final e in [..._commands.entries]) {
      if (!mine(e.value.as)) continue;
      _commands.remove(e.key);
      _ask({'op': 'undefine', 'name': e.key});
    }
    for (final e in [..._guards.entries]) {
      if (!mine(e.value.as)) continue;
      _guards.remove(e.key);
      _ask({'op': 'unguard', 'id': e.value.id, ..._asOf(e.value.as)});
    }
    for (final e in [..._kinds.entries]) {
      if (!mine(e.value.as)) continue;
      _kinds.remove(e.key);
      _ask({'op': 'unkind', 'name': e.key, ..._asOf(e.value.as)});
    }
    _parts.removeWhere((p, _) => p.isWithin(part));
  }

  @override
  void availabilityChanged(String command) {
    if (!_commands.containsKey(command)) {
      throw NotPermitted('$command is not $who\'s command');
    }
    _checkAvailability();
  }

  /// Tells the host what its commands' checks say now, where it changed.
  void _checkAvailability() {
    if (_disposed) return;
    for (final c in _commands.values) {
      final check = c.available;
      if (check == null) continue;
      final why = check();
      if (c.told && why == c.why) continue;
      c
        ..told = true
        ..why = why;
      _ask({
        'op': 'available',
        'command': c.d.name,
        'why': why,
        ..._asOf(c.as),
      });
    }
  }

  /// What each batch running now changed of its own states, as each was
  /// before it: undone if the batch throws. The innermost last.
  final List<Map<(String, String?), (bool, Object?)>> _undo = [];

  /// [state]'s value of [key] is about to change: kept as it was, for a
  /// batch running now to undo.
  void _changing(String state, String? key) {
    if (_undo.isEmpty) return;
    final values = _own[state];
    _undo.last.putIfAbsent((
      state,
      key,
    ), () => (values?.containsKey(key) ?? false, values?[key]));
  }

  /// Runs [writes], what it writes and says sent as one tick (SPEC §7).
  /// Whole or nothing, as in the host's process: when [writes] throws,
  /// nothing it wrote or said is sent, and its own states are as they were
  /// (an outer batch that catches it keeps what it wrote itself). What it
  /// defined stays defined, as there; what a call inside it sent is sent.
  @override
  void batch(void Function() writes) {
    _live();
    final before = Set<Map<String, Object?>>.identity()
      ..addAll(_queue)
      ..addAll(_away);
    _undo.add({});
    try {
      writes();
    } catch (_) {
      bool undone(Map<String, Object?> op) =>
          !before.contains(op) &&
          (op['op'] == 'set' || op['op'] == 'remove' || op['op'] == 'emit');
      _queue.removeWhere(undone);
      _away.removeWhere(undone);
      for (final MapEntry(key: (state, key), value: (had, was))
          in _undo.removeLast().entries) {
        if (had) {
          (_own[state] ??= {})[key] = was;
        } else {
          _own[state]?.remove(key);
        }
      }
      rethrow;
    }
    // An outer batch undoes what this one did too, if it throws.
    final done = _undo.removeLast();
    if (_undo.isNotEmpty) {
      for (final e in done.entries) {
        _undo.last.putIfAbsent(e.key, () => e.value);
      }
    }
  }

  late final OwnerGroup _group = OwnerGroup(this);

  @override
  Future<void> attach(Map<String, Owner> owners) {
    _live();
    _group.attach(owners);
    return flush();
  }

  @override
  void sync() => _group.sync();

  /// What it asked done, then the catalog as the host has it now: the feed
  /// brings the catalog in its own time, a status read after this is the
  /// host's as of then.
  @override
  Future<void> settle() async {
    _live();
    await OwnerGroup.idle();
    await flush();
    final d = await _asked(_client.describe);
    try {
      _mirror.takeCatalog(d);
    } on FormatException catch (e) {
      // The catalog it had stays; the host's defect is told.
      _fail(const {'op': 'describe'}, 'malformed', e.message);
    }
    // The states as the host had them then, and its listeners told.
    if (d case {'epoch': final String epoch, 'seq': final int seq}) {
      await _mirror.reach(epoch, seq);
    }
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void dispose() => unawaited(close());

  /// Withdraws its words, guards and kinds, stops its mirror and closes its
  /// endpoint.
  Future<void> close() async {
    if (_disposed) return;
    _retry?.cancel();
    _retry = null;
    // Owners attached to its parts go too, as a local participant's parts'.
    for (final part in [..._parts.values]) {
      part._group.dispose();
    }
    _group.dispose();
    for (final name in [..._own.keys, ..._facts.keys, ..._commands.keys]) {
      _ask({'op': 'undefine', 'name': name});
    }
    for (final g in _guards.values) {
      _ask({'op': 'unguard', 'id': g.id, ..._asOf(g.as)});
    }
    for (final k in _kinds.keys) {
      _ask({'op': 'unkind', 'name': k});
    }
    final unbuilt = _built.forget();
    if (_speaks.contains('built')) unbuilt.forEach(_ask);
    _disposed = true;
    for (final w in _watching.values) {
      unawaited(w.cancel());
    }
    _watching.clear();
    _own.clear();
    _states.clear();
    _facts.clear();
    _commands.clear();
    _guards.clear();
    _kinds.clear();
    await flush();
    await _connection?.cancel();
    await _changes?.cancel();
    await _mirror.dispose();
    await _errors.close();
    // The endpoint made on a connection is its own; the connection, and an
    // endpoint given to [over], stay the caller's.
    if (_ownsEndpoint) await endpoint.close();
  }

  // --- Asked by the host --------------------------------------------------

  Future<WireServed> _serve(WireServe request) async {
    final c = _commands[request.command];
    if (c == null) {
      return WireServed.failed('nothing serves ${request.command}');
    }
    final cause = Cause.fromJson(request.cause);
    final span = _callLog.startSpan(
      request.command,
      parent: request.traceparent,
    );
    // One the log keeps none of (no log, spans off) has no id: nothing
    // more is made for it.
    if (span.spanId.isNotEmpty) {
      span.addData({
        'call': request.id,
        'by': cause.by.selector,
        'conversation': cause.conversationOf(request.id),
      });
    }
    // Its deadline passes, unless the call ends first: no timer stays for
    // a call that is over.
    final expired = Completer<void>();
    final deadline = Timer(c.d.deadline, expired.complete);
    final call = CommandCall(
      request.id,
      request.command,
      request.params,
      cause,
      expired.future,
      span: span,
    );
    try {
      final value = await (c.d is QueryDescriptor
          ? asQuery(c.d.name, () => c.handler(call))
          : c.handler(call));
      // What it wrote in answer reaches the registry before the answer,
      // so it follows from the call.
      await flush();
      span.end();
      return WireServed.done(value);
    } on Object catch (e) {
      await flush();
      span.end(status: LogSpanStatus.error, error: e);
      return WireServed.failed('$e');
    } finally {
      deadline.cancel();
    }
  }

  WireJson _judge(Map<String, Object?> m) {
    final g = _guards[m['guard']];
    final c = _commands[m['command']];
    if (g == null || c == null) return const WireJson({});
    final why = g.check(
      PendingCall(
        m['id']! as String,
        c.d,
        (m['params'] as Map? ?? const {}).cast<String, Object?>(),
        Cause.fromJson(m['cause']),
      ),
    );
    return WireJson({'why': ?why});
  }
}
