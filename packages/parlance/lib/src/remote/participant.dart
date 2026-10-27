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
final class RemoteParticipant implements IParticipant {
  RemoteParticipant._(
    this.client,
    this.mirror,
    this.who,
    this.namespaces,
    this._onError,
  ) : _view = MirrorView(mirror, client);

  /// Joins the registry over [endpoint], a peer endpoint whose session the
  /// host made: its principal and namespaces are the session's.
  static Future<RemoteParticipant> connect(
    RpcPeerEndpoint endpoint, {
    void Function(ParticipantError error)? onError,
  }) async {
    final client = ParlanceClient(endpoint);
    final d = await client.describe();
    final p = RemoteParticipant._(
      client,
      RegistryMirror(),
      Principal.fromJson(d['principal']),
      {...(d['namespaces'] as List? ?? const []).cast<String>()},
      onError,
    );
    endpoint.registerServiceContract(_Served(endpoint, p));
    // It keeps of another's only what it watches: nothing to start with.
    unawaited(p.mirror.subscribe(states: const {}, facts: const {}));
    p.mirror.follow(client);
    p._changes = p.mirror.changes.listen((_) => p._checkAvailability());
    return p;
  }

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
  final Map<String, _Command> _commands = {};
  final Map<String, ({GuardCheck check, bool overridable})> _guards = {};
  final Map<String, EntityKind> _kinds = {};
  bool _disposed = false;

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

  Cause? _as(Cause? cause) {
    if (cause != null && cause.by != who) {
      throw NotPermitted('$who acts as itself, not as ${cause.by}');
    }
    return cause;
  }

  // --- What it asks, in order ---------------------------------------------

  final List<Map<String, Object?>> _queue = [];
  Future<void>? _sending;
  bool _scheduled = false;

  void _ask(Map<String, Object?> op) {
    _live();
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
      if (_queue.isEmpty) return;
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
        for (final op in ops) {
          _fail(op, 'lost', '$e');
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
  }) async {
    _live();
    final c = _as(cause);
    await flush();
    final r = await client.callAt(
      command,
      params,
      id: id,
      parent: c?.parent,
      test: c?.test ?? false,
    );
    if ((r.epoch, r.seq) case (final epoch?, final seq?)) {
      await mirror.reach(epoch, seq);
    }
    return r.result;
  }

  @override
  bool get synced => mirror.synced;

  @override
  WordStatus status(String word) => _view.status(word);

  @override
  Stream<WordStatus> statusChanges(String word) => _view.statusChanges(word);

  // --- Its own words ------------------------------------------------------

  @override
  IStateHandle defineState(StateDescriptor d) {
    _mayDefine(d);
    _ask({'op': 'define', 'descriptor': d.toJson()});
    _own[d.name] = {};
    return _State(this, d);
  }

  @override
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
  }) {
    _mayDefine(d);
    if (d.sets case final s? when !_owns(s.state)) {
      throw NotPermitted('${d.name} sets ${s.state}, a state not $who\'s');
    }
    _ask({'op': 'define', 'descriptor': d.toJson()});
    final c = _Command(d, handler, available);
    _commands[d.name] = c;
    return _Disposer(() {
      if (_commands[d.name] != c) return;
      _commands.remove(d.name);
      _ask({'op': 'undefine', 'name': d.name});
    });
  }

  @override
  IFactHandle defineFact(FactDescriptor d) {
    _mayDefine(d);
    _ask({'op': 'define', 'descriptor': d.toJson()});
    return _Fact(this, d, own: true);
  }

  /// Another producer of an open [fact]; the host's rights decide, and a
  /// refusal comes to [errors] with its first fact.
  @override
  IFactHandle producer(String fact) {
    _live();
    return _Fact(
      this,
      FactDescriptor(fact, type: const AnyType(), open: true),
      own: false,
    );
  }

  /// A guard on its own commands, asked by the host in its turn (§10); a
  /// call it is not asked about in time is denied there.
  @override
  IHandle addGuard(String id, GuardCheck check, {bool overridable = true}) {
    _live();
    _guards[id] = (check: check, overridable: overridable);
    _ask({'op': 'guard', 'id': id, 'overridable': overridable});
    return _Disposer(() {
      if (_guards.remove(id) == null) return;
      _ask({'op': 'unguard', 'id': id});
    });
  }

  @override
  IHandle registerKind(EntityKind kind) {
    _live();
    _kinds[kind.name] = kind;
    _sendKind(kind);
    return _Disposer(() {
      if (_kinds.remove(kind.name) == null) return;
      _ask({'op': 'unkind', 'name': kind.name});
    });
  }

  void _sendKind(EntityKind kind) => _ask({
    'op': 'kind',
    'name': kind.name,
    'entities': [for (final e in kind.list()) e.toJson()],
  });

  @override
  void entitiesChanged(String kind) {
    final k = _kinds[kind];
    if (k == null) throw NotPermitted('$who registered no kind $kind');
    _sendKind(k);
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
      _ask({'op': 'available', 'command': c.d.name, 'why': why});
    }
  }

  @override
  void batch(void Function() writes) => writes();

  @override
  void dispose() => unawaited(close());

  /// Withdraws its words, guards and kinds, and stops its mirror.
  Future<void> close() async {
    if (_disposed) return;
    for (final name in [..._own.keys, ..._commands.keys]) {
      _ask({'op': 'undefine', 'name': name});
    }
    for (final id in _guards.keys) {
      _ask({'op': 'unguard', 'id': id});
    }
    for (final k in _kinds.keys) {
      _ask({'op': 'unkind', 'name': k});
    }
    _disposed = true;
    _own.clear();
    _commands.clear();
    _guards.clear();
    _kinds.clear();
    await flush();
    await _changes?.cancel();
    await mirror.dispose();
    await _errors.close();
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
      final value = await c.handler(call);
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
  _Command(this.d, this.handler, this.available);
  final CommandDescriptor d;
  final CommandHandler handler;
  final Availability? available;

  /// What its check said last, told to the host.
  String? why;
  bool told = false;
}

final class _State implements IStateHandle {
  _State(this._p, this.descriptor);
  final RemoteParticipant _p;

  @override
  final StateDescriptor descriptor;

  @override
  void set(Object? value, {String? key, Cause? cause}) {
    final c = _p._as(cause);
    final v = freezeJson(value);
    _p._ask({
      'op': 'set',
      'state': descriptor.name,
      'key': ?key,
      'value': v,
      ...RemoteParticipant._causeOf(c),
    });
    (_p._own[descriptor.name] ??= {})[key] = v;
  }

  @override
  void remove({String? key, Cause? cause}) {
    final c = _p._as(cause);
    _p._ask({
      'op': 'remove',
      'state': descriptor.name,
      'key': ?key,
      ...RemoteParticipant._causeOf(c),
    });
    _p._own[descriptor.name]?.remove(key);
  }

  @override
  void dispose() {
    if (_p._own.remove(descriptor.name) == null) return;
    _p._ask({'op': 'undefine', 'name': descriptor.name});
  }
}

final class _Fact implements IFactHandle {
  _Fact(this._p, this.descriptor, {required this.own});
  final RemoteParticipant _p;
  final bool own;

  @override
  final FactDescriptor descriptor;

  /// Says [payload]. True: whether the registry took it (a repeat of [id]
  /// is dropped there) is not known when it is said.
  @override
  bool emit(Object? payload, {String? id, Cause? cause}) {
    final by = cause != null && cause.by != _p.who ? cause.by : null;
    _p._ask({
      'op': 'emit',
      'fact': descriptor.name,
      'payload': freezeJson(payload),
      'id': ?id,
      'by': ?by?.toJson(),
      ...RemoteParticipant._causeOf(cause),
    });
    return true;
  }

  @override
  void dispose() {
    if (!own) return;
    _p._ask({'op': 'undefine', 'name': descriptor.name});
  }
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
