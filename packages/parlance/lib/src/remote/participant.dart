import 'dart:async';

import 'package:clock/clock.dart' as clock_zone;
import 'package:clock/clock.dart' show Clock;
import 'package:rpc_dart/rpc_dart.dart';

import '../participant/participant.dart';
import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/json.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/types.dart';
import '../view/mirror_view.dart';
import 'contract.dart';
import 'remote.dart';

/// What a remote participant asked and the registry refused, told after:
/// over a connection the answer is not there when the participant asks
/// (SPEC §22.4).
final class ParticipantError {
  const ParticipantError(this.op, this.code, this.message);

  /// What it asked, as it was sent (`{op: define, descriptor: ...}`).
  final Map<String, Object?> op;

  /// The session's status: `permissionDenied`, `alreadyExists`,
  /// `invalidArgument`, `notFound`; `lost` when the answer did not come.
  final String code;
  final String message;

  @override
  String toString() => '${op['op']}: $code: $message';
}

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
    this.client,
    this.mirror,
    this.who,
    this.namespaces,
    this.access,
    this._onError,
  ) : _view = MirrorView(mirror, client);

  @override
  final WordAccess access;

  /// Joins the registry over [connection], starting it when it is idle:
  /// the participant makes its peer endpoint on the connection's transport
  /// ([endpoint], for other contracts on the same connection), waits until
  /// it is online, and joins again each time it is back. Its principal and
  /// namespaces are the session's the host made.
  static Future<RemoteParticipant> join(
    RpcClientConnection connection, {
    WordAccess access = WordAccess.none,
    void Function(ParticipantError error)? onError,
  }) async {
    final endpoint = RpcPeerEndpoint(transport: connection.transport)..start();
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
    final client = ParlanceClient(endpoint);
    final d = await client.describe();
    final p = RemoteParticipant._(
      endpoint,
      client,
      RegistryMirror(),
      Principal.fromJson(d['principal']),
      {...(d['namespaces'] as List? ?? const []).cast<String>()},
      access,
      onError,
    );
    endpoint.registerServiceContract(_Served(endpoint, p));
    // It keeps of another's only what it watches: nothing to start with.
    unawaited(p.mirror.subscribe(states: const {}, facts: const {}));
    p.mirror.follow(client);
    p._changes = p.mirror.changes.listen((_) => p._checkAvailability());
    p._connection = connection.state.listen(p._onConnection);
    return p;
  }

  StreamSubscription<RpcClientConnectionState>? _connection;

  /// Whether its session is there to ask: false from a drop until it has
  /// joined the host's new session.
  bool _online = true;
  bool _rejoining = false;

  void _onConnection(RpcClientConnectionState s) {
    switch (s) {
      case RpcClientOnline():
        if (!_online) unawaited(_rejoin());
      case RpcClientOffline() || RpcClientConnecting():
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
      final d = await client.describe();
      final now = Principal.fromJson(d['principal']);
      if (now != who) {
        _fail(
          const {'op': 'rejoin'},
          'permissionDenied',
          'the new session is $now\'s, not $who\'s',
        );
        return;
      }
      _queue.insertAll(0, _standing());
      for (final c in _commands.values) {
        c.told = false;
      }
      _online = true;
      mirror.follow(client);
      _checkAvailability();
      await flush();
    } on Object {
      // Dropped again before it joined: the next time it is online.
      _online = false;
    } finally {
      _rejoining = false;
    }
  }

  /// What it has defined, as it stands now, in the order a session takes
  /// it: kinds before the values that name their entities, states before
  /// the commands that set them.
  List<Map<String, Object?>> _standing() => [
    for (final k in _kinds.values) _kindOp(k.kind, k.as),
    for (final MapEntry(key: part, value: d) in _declared.entries)
      _declareOp(d, part),
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
  ];

  /// The peer endpoint it made on its connection.
  final RpcPeerEndpoint endpoint;
  final ParlanceClient client;
  final RegistryMirror mirror;
  final MirrorView _view;
  final void Function(ParticipantError error)? _onError;
  StreamSubscription<void>? _changes;

  @override
  final Principal who;

  @override
  final Set<String> namespaces;

  final StreamController<ParticipantError> _errors =
      StreamController.broadcast();

  /// What the registry refused of what it asked.
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

  /// What it and each part said of itself, by the part (null: itself).
  final Map<Principal?, Declaration> _declared = {};
  final Map<Principal, _Part> _parts = {};
  bool _disposed = false;

  static Map<String, Object?> _asOf(Principal? as) => {'as': ?as?.toJson()};

  @override
  Clock get clock => clock_zone.clock;

  void _live() {
    if (_disposed) throw StateError('participant $who is gone');
  }

  bool _owns(String name) =>
      namespaces.any((ns) => name == ns || name.startsWith('$ns.'));

  void _mayDefine(Descriptor d) {
    _live();
    if (!_owns(d.name)) {
      throw NotPermitted(
        '$who defines in ${namespaces.isEmpty ? 'no namespace' : namespaces.join(', ')}, not ${d.name}',
      );
    }
  }

  /// Whether a cause by [by] is [speaker]'s own act: [speaker] itself, or
  /// a whole it is part of, up to this participant.
  bool _ownAct(Principal by, Principal speaker) =>
      by == speaker || (speaker.isWithin(by) && by.isWithin(who));

  Cause? _as(Cause? cause, [Principal? speaker]) {
    final s = speaker ?? who;
    if (cause != null && !_ownAct(cause.by, s)) {
      throw NotPermitted('$s acts as itself, not as ${cause.by}');
    }
    return cause;
  }

  // --- What it asks, in order ---------------------------------------------

  final List<Map<String, Object?>> _queue = [];
  Future<void>? _sending;
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
    if (!_online && op['op'] != 'emit') return;
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

  /// Completes when the registry has answered all it asked so far.
  Future<void> flush() async {
    while (true) {
      if (_sending case final s?) {
        await s;
        continue;
      }
      if (_queue.isEmpty || !_online) return;
      final ops = [..._queue];
      _queue.clear();
      final done = Completer<void>();
      _sending = done.future;
      try {
        final results = await client.apply(ops);
        for (var i = 0; i < ops.length && i < results.length; i++) {
          if (results[i]['error'] case final String code) {
            _fail(ops[i], code, '${results[i]['message']}');
          }
        }
      } on Object catch (e) {
        if (!_disposed) {
          // The connection dropped: a new session gets what it defined as
          // it stands; what it said goes again after, its ids letting the
          // registry drop one it took.
          _online = false;
          _queue.insertAll(0, [
            for (final op in ops)
              if (op['op'] == 'emit') op,
          ]);
        } else {
          for (final op in ops) {
            _fail(op, 'lost', '$e');
          }
        }
      } finally {
        _sending = null;
        done.complete();
      }
    }
  }

  void _fail(Map<String, Object?> op, String code, String message) {
    final e = ParticipantError(op, code, message);
    _onError?.call(e);
    if (!_errors.isClosed) _errors.add(e);
  }

  static Map<String, Object?> _causeOf(Cause? cause) => {
    'parent': ?cause?.parent,
    if (cause?.test ?? false) 'test': true,
  };

  // --- Reading and calling, as [who] --------------------------------------

  @override
  Object? read(String state, {String? key}) =>
      _own.containsKey(state) ? _own[state]![key] : _view.read(state, key: key);

  @override
  Map<String?, Object?> readAll(String state) => _own.containsKey(state)
      ? Map.unmodifiable(_own[state]!)
      : _view.readAll(state);

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
  Stream<void> changes(Set<String> states) => _view.changes(states);

  @override
  Stream<FactMessage> facts(String fact) => _view.facts(fact);

  @override
  Future<List<FactMessage>> recent(String fact, int count) =>
      _view.recent(fact, count);

  /// Calls [command] as [who], after what it asked before has been done.
  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
  }) => _call(command, params, id: id, cause: cause);

  Future<CallResult<Object?>> _call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
    Principal? as,
  }) async {
    _live();
    final c = _as(cause, as);
    // A query's handler may ask another query, never call a command.
    if (answeringQuery() != null && !_isQuery(command)) {
      refuseInQuery('call $command');
    }
    await flush();
    final r = await client.callAt(
      command,
      params,
      id: id,
      parent: c?.parent,
      test: c?.test ?? false,
      as: as,
    );
    if ((r.epoch, r.seq) case (final epoch?, final seq?)) {
      await mirror.reach(epoch, seq);
    }
    return r.result;
  }

  /// Whether [command] is a query, as the catalog says.
  bool _isQuery(String command) {
    final name = mirror.canonical(command);
    for (final d in mirror.catalog['descriptors'] as List? ?? const []) {
      if (d case {'name': final n, 'is': 'query'} when n == name) return true;
    }
    return false;
  }

  @override
  bool get synced => mirror.synced;

  @override
  WordStatus status(String word) => _view.status(word);

  @override
  Stream<WordStatus> statusChanges(String word) => _view.statusChanges(word);

  // --- Its own words ------------------------------------------------------

  @override
  IStateHandle defineState(StateDescriptor d) => _defineState(d, null);

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
  }) => _defineCommand(d, handler, available, null);

  @override
  IHandle defineQuery(
    QueryDescriptor d,
    CommandHandler handler, {
    Availability? available,
  }) => _defineCommand(d, handler, available, null);

  /// A command or a query of its own, or of [as], a part of it.
  IHandle _defineCommand(
    CallableDescriptor d,
    CommandHandler handler,
    Availability? available,
    Principal? as,
  ) {
    _mayDefine(d);
    if (d case CommandDescriptor(sets: final s?) when !_owns(s.state)) {
      throw NotPermitted('${d.name} sets ${s.state}, a state not $who\'s');
    }
    _ask({'op': 'define', 'descriptor': d.toJson(), ..._asOf(as)});
    final c = _Command(d, handler, available, as);
    _commands[d.name] = c;
    return _Disposer(() {
      if (_commands[d.name] != c) return;
      _commands.remove(d.name);
      _ask({'op': 'undefine', 'name': d.name});
    });
  }

  @override
  IFactHandle defineFact(FactDescriptor d) => _defineFact(d, null);

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
  IFactHandle producer(String fact) => _producer(fact, null);

  IFactHandle _producer(String fact, Principal? as) {
    _live();
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
    final full = '${(as ?? who).selector}/$id';
    _guards[full] = (id: id, check: check, overridable: overridable, as: as);
    _ask({'op': 'guard', 'id': id, 'overridable': overridable, ..._asOf(as)});
    return _Disposer(() {
      if (_guards.remove(full) == null) return;
      _ask({'op': 'unguard', 'id': id, ..._asOf(as)});
    });
  }

  @override
  IHandle declare(Declaration d) => _declare(d, null);

  IHandle _declare(Declaration d, Principal? as) {
    _live();
    for (final name in d.owns) {
      if (!_owns(name)) {
        throw NotPermitted(
          '${as ?? who} owns words in ${namespaces.join(', ')}, not $name',
        );
      }
    }
    _declared[as] = d;
    _ask(_declareOp(d, as));
    return _Disposer(() {
      if (_declared[as] != d) return;
      _declared.remove(as);
      _ask({'op': 'undeclare', ..._asOf(as)});
    });
  }

  static Map<String, Object?> _declareOp(Declaration d, Principal? as) => {
    'op': 'declare',
    'declaration': d.toJson(),
    ..._asOf(as),
  };

  @override
  IHandle registerKind(EntityKind kind) => _registerKind(kind, null);

  IHandle _registerKind(EntityKind kind, Principal? as) {
    _live();
    _kinds[kind.name] = (kind: kind, as: as);
    _ask(_kindOp(kind, as));
    return _Disposer(() {
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
    for (final as in [..._declared.keys]) {
      if (!mine(as)) continue;
      _declared.remove(as);
      _ask({'op': 'undeclare', ..._asOf(as)});
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

  @override
  void batch(void Function() writes) => writes();

  /// What it asked done, then the catalog as the host has it now: the feed
  /// brings the catalog in its own time, a status read after this is the
  /// host's as of then.
  @override
  Future<void> settle() async {
    _live();
    await flush();
    mirror.takeCatalog(await client.describe());
  }

  @override
  void dispose() => unawaited(close());

  /// Withdraws its words, guards and kinds, stops its mirror and closes its
  /// endpoint.
  Future<void> close() async {
    if (_disposed) return;
    for (final name in [..._own.keys, ..._facts.keys, ..._commands.keys]) {
      _ask({'op': 'undefine', 'name': name});
    }
    for (final g in _guards.values) {
      _ask({'op': 'unguard', 'id': g.id, ..._asOf(g.as)});
    }
    for (final k in _kinds.keys) {
      _ask({'op': 'unkind', 'name': k});
    }
    for (final as in _declared.keys) {
      _ask({'op': 'undeclare', ..._asOf(as)});
    }
    _disposed = true;
    _own.clear();
    _states.clear();
    _facts.clear();
    _commands.clear();
    _guards.clear();
    _kinds.clear();
    _declared.clear();
    await flush();
    await _connection?.cancel();
    await _changes?.cancel();
    await mirror.dispose();
    await _errors.close();
    // The endpoint is its own; the connection stays the caller's to
    // dispose.
    await endpoint.close();
  }

  // --- Asked by the host --------------------------------------------------

  Future<SbServed> _serve(SbServe request) async {
    final c = _commands[request.command];
    if (c == null) return SbServed.failed('nothing serves ${request.command}');
    final call = CommandCall(
      request.id,
      request.command,
      request.params,
      Cause.fromJson(request.cause),
      Future<void>.delayed(c.d.deadline),
    );
    try {
      final value = await (c.d is QueryDescriptor
          ? asQuery(c.d.name, () => c.handler(call))
          : c.handler(call));
      // What it wrote in answer reaches the registry before the answer,
      // so it follows from the call.
      await flush();
      return SbServed.done(value);
    } on Object catch (e) {
      await flush();
      return SbServed.failed('$e');
    }
  }

  SbJson _judge(Map<String, Object?> m) {
    final g = _guards[m['guard']];
    final c = _commands[m['command']];
    if (g == null || c == null) return const SbJson({});
    final why = g.check(
      PendingCall(
        m['id']! as String,
        c.d,
        (m['params'] as Map? ?? const {}).cast<String, Object?>(),
        Cause.fromJson(m['cause']),
        layerDispatch: m['layer'] == true,
      ),
    );
    return SbJson({'why': ?why});
  }
}

final class _Command {
  _Command(this.d, this.handler, this.available, this.as);

  /// A command's or a query's.
  final CallableDescriptor d;
  final CommandHandler handler;
  final Availability? available;

  /// The part that defined it; null for the participant itself.
  final Principal? as;

  /// What its check said last, told to the host.
  String? why;
  bool told = false;
}

final class _State implements IStateHandle {
  _State(this._p, this.descriptor, this._by);
  final RemoteParticipant _p;

  /// The part that defined it; null for the participant itself.
  final Principal? _by;

  @override
  final StateDescriptor descriptor;

  @override
  void set(Object? value, {String? key, Cause? cause}) {
    final c = _p._as(cause, _by);
    final v = freezeJson(value);
    _p._ask({
      'op': 'set',
      'state': descriptor.name,
      'key': ?key,
      'value': v,
      ...RemoteParticipant._causeOf(c),
      ...RemoteParticipant._asOf(_by),
    });
    (_p._own[descriptor.name] ??= {})[key] = v;
  }

  @override
  void remove({String? key, Cause? cause}) {
    final c = _p._as(cause, _by);
    _p._ask({
      'op': 'remove',
      'state': descriptor.name,
      'key': ?key,
      ...RemoteParticipant._causeOf(c),
      ...RemoteParticipant._asOf(_by),
    });
    _p._own[descriptor.name]?.remove(key);
  }

  @override
  void dispose() {
    _p._states.remove(descriptor.name);
    if (_p._own.remove(descriptor.name) == null) return;
    _p._ask({'op': 'undefine', 'name': descriptor.name});
  }
}

final class _Fact implements IFactHandle {
  _Fact(this._p, this.descriptor, {required this.own, Principal? as})
    : _by = as;
  final RemoteParticipant _p;
  final bool own;

  /// The part that says it; null for the participant itself.
  final Principal? _by;

  @override
  final FactDescriptor descriptor;

  /// Says [payload]. True: whether the registry took it (a repeat of [id]
  /// is dropped there) is not known when it is said.
  @override
  bool emit(Object? payload, {String? id, Cause? cause}) {
    final speaker = _by ?? _p.who;
    final by = cause != null && !_p._ownAct(cause.by, speaker)
        ? cause.by
        : null;
    _p._ask({
      'op': 'emit',
      'fact': descriptor.name,
      'payload': freezeJson(payload),
      'id': ?id,
      'by': ?by?.toJson(),
      ...RemoteParticipant._causeOf(cause),
      ...RemoteParticipant._asOf(_by),
    });
    return true;
  }

  @override
  void dispose() {
    if (!own || _p._facts.remove(descriptor.name) == null) return;
    _p._ask({'op': 'undefine', 'name': descriptor.name});
  }
}

/// A part of a remote participant (SPEC §22.3): the participant's own
/// machinery, each thing it asks told as the part's (`as`).
final class _Part implements IParticipant {
  _Part(this._root, this.who);
  final RemoteParticipant _root;

  @override
  final Principal who;

  @override
  Set<String> get namespaces => _root.namespaces;

  @override
  WordAccess get access => _root.access;

  @override
  Clock get clock => _root.clock;

  @override
  Object? read(String state, {String? key}) => _root.read(state, key: key);

  @override
  Map<String?, Object?> readAll(String state) => _root.readAll(state);

  @override
  Stream<Object?> watch(String state, {String? key}) =>
      _root.watch(state, key: key);

  @override
  Stream<void> changes(Set<String> states) => _root.changes(states);

  @override
  Stream<FactMessage> facts(String fact) => _root.facts(fact);

  @override
  Future<List<FactMessage>> recent(String fact, int count) =>
      _root.recent(fact, count);

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
  }) => _root._call(command, params, id: id, cause: cause, as: who);

  @override
  bool get synced => _root.synced;

  @override
  WordStatus status(String word) => _root.status(word);

  @override
  Stream<WordStatus> statusChanges(String word) => _root.statusChanges(word);

  @override
  IStateHandle defineState(StateDescriptor d) => _root._defineState(d, who);

  @override
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
  }) => _root._defineCommand(d, handler, available, who);

  @override
  IHandle defineQuery(
    QueryDescriptor d,
    CommandHandler handler, {
    Availability? available,
  }) => _root._defineCommand(d, handler, available, who);

  @override
  IFactHandle defineFact(FactDescriptor d) => _root._defineFact(d, who);

  @override
  IFactHandle producer(String fact) => _root._producer(fact, who);

  @override
  IHandle addGuard(String id, GuardCheck check, {bool overridable = true}) =>
      _root._addGuard(id, check, overridable, who);

  @override
  IHandle registerKind(EntityKind kind) => _root._registerKind(kind, who);

  @override
  IHandle declare(Declaration d) => _root._declare(d, who);

  @override
  void entitiesChanged(String kind) => _root.entitiesChanged(kind);

  @override
  void availabilityChanged(String command) =>
      _root.availabilityChanged(command);

  @override
  void batch(void Function() writes) => _root.batch(writes);

  @override
  Future<void> settle() => _root.settle();

  @override
  IParticipant child(String name) => _root._partOf(who.child(name));

  @override
  void dispose() => _root._withdraw(who);
}

final class _Served extends ParlanceOwnerContractPeer {
  _Served(super.endpoint, this._p);
  final RemoteParticipant _p;

  @override
  Future<SbServed> onServe(SbServe request, {RpcContext? context}) =>
      _p._serve(request);

  @override
  Future<SbJson> onJudge(SbJson request, {RpcContext? context}) async =>
      _p._judge(request.json);
}

final class _Disposer implements IHandle {
  _Disposer(this._f);
  void Function()? _f;

  @override
  void dispose() {
    final f = _f;
    _f = null;
    f?.call();
  }
}
