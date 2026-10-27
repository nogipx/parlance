import 'package:clock/clock.dart' show Clock;

import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../view/view.dart';
import 'participant.dart';

/// Participants of a registry in this process (SPEC §22.1).
extension Participants on Registry {
  /// A participant speaking as [who], defining words in [namespaces] only.
  /// A namespace is one participant's: one that another live participant
  /// has, or one inside or around it (`orders` and `orders.archive`), is
  /// refused.
  LocalParticipant participant(
    Principal who, {
    Set<String> namespaces = const {},
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
  }) {
    final taken = _namespaces[this] ??= {};
    for (final ns in namespaces) {
      checkName(ns, 'namespace');
      for (final e in taken.entries) {
        if (_overlap(ns, e.key)) {
          throw NotPermitted('namespace $ns: ${e.key} is ${e.value.who}\'s');
        }
      }
    }
    final p = LocalParticipant._(
      this,
      who,
      Set.unmodifiable(namespaces),
      rights,
      access,
    );
    for (final ns in namespaces) {
      taken[ns] = p;
    }
    return p;
  }
}

final Expando<Map<String, LocalParticipant>> _namespaces = Expando();

bool _overlap(String a, String b) =>
    a == b || a.startsWith('$b.') || b.startsWith('$a.');

/// A participant of a registry in this process: the registry as [who] may
/// use it.
final class LocalParticipant implements IParticipant {
  LocalParticipant._(
    this._r,
    this.who,
    this.namespaces,
    this.rights,
    this.access, {
    this.parent,
  }) : _view = LocalView(_r, by: who);

  /// The participant this one is a part of ([child]); null for a whole.
  final LocalParticipant? parent;

  final Map<String, LocalParticipant> _children = {};

  @override
  final WordAccess access;

  final Registry _r;
  final LocalView _view;

  @override
  final Principal who;

  @override
  final Set<String> namespaces;

  /// What it may do beyond defining in its namespaces.
  final ParticipantRights rights;

  /// What it defined, registered and added, to withdraw on [dispose].
  final List<IHandle> _handles = [];

  /// The commands it defined: its guards judge their calls only.
  final Set<String> _commands = {};

  /// The kinds it registered.
  final Set<String> _kinds = {};
  bool _disposed = false;

  @override
  Clock get clock => _r.clock;

  void _live() {
    if (_disposed) throw StateError('participant $who is gone');
  }

  H _keep<H extends IHandle>(H h) {
    _handles.add(h);
    return h;
  }

  /// Whether [name] is in its namespaces.
  bool owns(String name) =>
      namespaces.any((ns) => name == ns || name.startsWith('$ns.'));

  void _mayDefine(Descriptor d) {
    _live();
    if (!owns(d.name)) {
      throw NotPermitted(
        '$who defines in ${namespaces.isEmpty ? 'no namespace' : namespaces.join(', ')}, not ${d.name}',
      );
    }
    if (rights.define?.call(who, d) case final why?) throw NotPermitted(why);
  }

  /// [cause], or its own: what it writes and calls is its own act, or
  /// follows from a call it serves (`call.causeFor(who)`). A part takes a
  /// cause of a whole it is part of as its own: what it does is its own.
  Cause _as(Cause? cause) {
    if (cause == null) return Cause(who);
    if (cause.by == who) return cause;
    if (_wholeOf(cause.by)) {
      return Cause(
        who,
        parent: cause.parent,
        chain: cause.chain,
        test: cause.test,
      );
    }
    throw NotPermitted('$who acts as itself, not as ${cause.by}');
  }

  /// Whether [p] is a participant this one is a part of.
  bool _wholeOf(Principal p) {
    for (var w = parent; w != null; w = w.parent) {
      if (w.who == p) return true;
    }
    return false;
  }

  /// A part of it, named [name] (SPEC §22.3): it speaks as `who.child(name)`
  /// in the same namespaces, with the same rights and access; what it
  /// defines and does is told as its own, and its guards judge its own
  /// commands. One part per name; it goes with this one.
  @override
  LocalParticipant child(String name) {
    _live();
    return _children[name] ??= LocalParticipant._(
      _r,
      who.child(name),
      namespaces,
      rights,
      access,
      parent: this,
    );
  }

  // --- Reading and calling, as [who] --------------------------------------

  @override
  Object? read(String state, {String? key}) => _view.read(state, key: key);

  @override
  Map<String?, Object?> readAll(String state) => _view.readAll(state);

  @override
  Stream<Object?> watch(String state, {String? key}) =>
      _r.mayRead(who, state) ? _r.watch(state, key: key) : Stream.value(null);

  @override
  Stream<void> changes(Set<String> states) => _view.changes(states);

  @override
  Stream<FactMessage> facts(String fact) => _view.facts(fact);

  @override
  Future<List<FactMessage>> recent(String fact, int count) =>
      _view.recent(fact, count);

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
  }) {
    _live();
    final c = _as(cause);
    return _r.call(command, params, by: who, id: id, cause: c);
  }

  @override
  bool get synced => true;

  @override
  WordStatus status(String word) => _view.status(word);

  @override
  Stream<WordStatus> statusChanges(String word) => _view.statusChanges(word);

  // --- Its own words ------------------------------------------------------

  @override
  IStateHandle defineState(StateDescriptor d) {
    _mayDefine(d);
    return _keep(_OwnState(this, _r.defineState(access.state(d), by: who)));
  }

  @override
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
  }) {
    _mayDefine(d);
    if (d.sets case final s? when !owns(s.state)) {
      throw NotPermitted('${d.name} sets ${s.state}, a state not $who\'s');
    }
    final h = _r.defineCommand(d, handler, available: available);
    _commands.add(d.name);
    return _keep(
      _Disposer(() {
        _commands.remove(d.name);
        h.dispose();
      }),
    );
  }

  @override
  IFactHandle defineFact(FactDescriptor d) {
    _mayDefine(d);
    return _keep(_OwnFact(this, _r.defineFact(access.fact(d), by: who)));
  }

  @override
  IFactHandle producer(String fact) {
    _live();
    final check = rights.produce;
    if ((check == null ? '$who may produce nothing' : check(who, fact))
        case final why?) {
      throw NotPermitted(why);
    }
    return _keep(_OwnFact(this, _r.producer(fact, by: who)));
  }

  @override
  IHandle addGuard(String id, GuardCheck check, {bool overridable = true}) {
    _live();
    return _keep(
      _r.addGuard(
        id,
        (c) => _commands.contains(c.command.name) ? check(c) : null,
        overridable: overridable,
      ),
    );
  }

  /// A guard of its own whose check it makes across a connection (SPEC
  /// §22.4): the host's side of a remote participant's guard.
  IHandle addAskedGuard(
    String id,
    Future<String?> Function(PendingCall call) ask, {
    bool overridable = true,
    Duration timeout = const Duration(seconds: 2),
  }) {
    _live();
    return _keep(
      _r.addAskedGuard(
        id,
        (c) async => _commands.contains(c.command.name) ? ask(c) : null,
        overridable: overridable,
        timeout: timeout,
      ),
    );
  }

  @override
  void availabilityChanged(String command) {
    if (!_commands.contains(_r.canonical(command))) {
      throw NotPermitted('$command is not $who\'s command');
    }
    _r.availabilityChanged(command);
  }

  @override
  IHandle registerKind(EntityKind kind) {
    _live();
    final h = _r.registerKind(kind);
    _kinds.add(kind.name);
    return _keep(
      _Disposer(() {
        _kinds.remove(kind.name);
        h.dispose();
      }),
    );
  }

  @override
  void entitiesChanged(String kind) {
    if (!_kinds.contains(kind)) {
      throw NotPermitted('$who registered no kind $kind');
    }
    _r.entitiesChanged(kind);
  }

  @override
  void batch(void Function() writes) => _r.batch(writes);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final c in [..._children.values].reversed) {
      c.dispose();
    }
    for (final h in _handles.reversed) {
      h.dispose();
    }
    _handles.clear();
    if (parent case final p?) {
      p._children.removeWhere((_, c) => c == this);
      return;
    }
    final taken = _namespaces[_r];
    taken?.removeWhere((_, p) => p == this);
  }
}

/// A state of a participant's: written as the participant only.
final class _OwnState implements IStateHandle {
  _OwnState(this._p, this._raw);
  final LocalParticipant _p;
  final RawStateWriter _raw;

  @override
  StateDescriptor get descriptor => _raw.descriptor;

  @override
  void set(Object? value, {String? key, Cause? cause}) =>
      _raw.set(value, key: key, cause: _p._as(cause));

  @override
  void remove({String? key, Cause? cause}) =>
      _raw.remove(key: key, cause: _p._as(cause));

  @override
  void dispose() => _raw.dispose();
}

/// A fact a participant says: as itself, or on behalf of another when its
/// rights let it.
final class _OwnFact implements IFactHandle {
  _OwnFact(this._p, this._raw);
  final LocalParticipant _p;
  final RawFactEmitter _raw;

  @override
  FactDescriptor get descriptor => _raw.descriptor;

  @override
  bool emit(Object? payload, {String? id, Cause? cause}) {
    final p = _p;
    if (cause != null && cause.by != p.who && !p._wholeOf(cause.by)) {
      final check = p.rights.speakFor;
      if ((check == null
              ? '${p.who} may speak for no one'
              : check(p.who, cause.by, descriptor.name))
          case final why?) {
        throw NotPermitted(why);
      }
    }
    final own = cause == null || cause.by == p.who || p._wholeOf(cause.by);
    return _raw.emit(payload, id: id, cause: own ? p._as(cause) : cause);
  }

  @override
  void dispose() => _raw.dispose();
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
