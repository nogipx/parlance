import 'package:clock/clock.dart' show Clock;

import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/shapes.dart';
import '../registry/words.dart';
import '../view/view.dart';
import 'owner.dart';
import 'participant.dart';

/// Participants of a registry in this process (SPEC §22.1).
extension Participants on Registry {
  /// A participant speaking as [who], defining words only in its
  /// [vocabularies] (SPEC §22.1, §23); one whose words come at run time is
  /// `WordSet.open`. A word is named in its vocabulary: `orders.cancel` is
  /// in `orders`. Two of [vocabularies] of one name, or one inside the
  /// other (`orders` and `orders.archive`), are refused, so the words
  /// named under a vocabulary are those of one owner. A vocabulary is one
  /// participant's: one that another live participant has, or one inside
  /// or around it, is refused.
  LocalParticipant participant(
    Principal who, {
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
  }) {
    who.check();
    access.read?.check();
    access.call?.check();
    for (final v in vocabularies) {
      v.check();
    }
    final given = [for (final v in vocabularies) v.name];
    for (final (i, a) in given.indexed) {
      for (final b in given.skip(i + 1)) {
        if (_overlap(a, b)) {
          throw ArgumentError.value(
            vocabularies,
            'vocabularies',
            a == b
                ? 'the vocabulary $a is given twice'
                : 'the vocabularies $a and $b: one inside the other',
          );
        }
      }
    }
    final names = given.toSet();
    final taken = _taken[this] ??= {};
    for (final ns in names) {
      checkName(ns, 'vocabulary');
      for (final e in taken.entries) {
        if (_overlap(ns, e.key)) {
          throw NotPermitted('vocabulary $ns: ${e.key} is ${e.value.who}\'s');
        }
      }
    }
    final p = LocalParticipant._(
      this,
      who,
      Set.unmodifiable(names),
      rights,
      access,
    );
    for (final ns in names) {
      taken[ns] = p;
    }
    return p;
  }
}

/// The vocabularies taken, by name, and whose they are.
final Expando<Map<String, LocalParticipant>> _taken = Expando();

bool _overlap(String a, String b) =>
    a == b || a.startsWith('$b.') || b.startsWith('$a.');

/// A participant of a registry in this process: the registry as [who] may
/// use it.
/// The registry [p] speaks to: the package's own, for a session that
/// serves [p] across a connection (`serve`); not exported, so a part given
/// a participant never holds the registry.
Registry registryOf(LocalParticipant p) => p._r;

/// Takes [p] for a session to serve (`serve`): one participant, one
/// session, and only a new one, so the session owns all it has. Refused
/// for one served already, or one that did anything here: its words,
/// guards, kinds, owners or parts would go with the session. Not exported.
void takeForServing(LocalParticipant p) {
  p._live();
  if (p._served) throw StateError('${p.who} is served already');
  if (p._handles.isNotEmpty ||
      p._children.isNotEmpty ||
      p._group.owners.isNotEmpty) {
    throw StateError(
      '${p.who} did things in this process: serve a participant made for '
      'the session',
    );
  }
  p._served = true;
}

final class LocalParticipant implements IParticipant {
  LocalParticipant._(
    this._r,
    this.who,
    this.vocabularies,
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
  final Set<String> vocabularies;

  /// What it may do beyond defining in its vocabularies.
  final ParticipantRights rights;

  /// What it defined, registered and added, to withdraw on [dispose]: each
  /// leaves it when withdrawn on its own.
  final Set<IHandle> _handles = {};

  /// The commands it defined: its guards judge their calls only.
  final Set<String> _commands = {};

  /// The kinds it registered.
  final Set<String> _kinds = {};
  bool _disposed = false;
  bool _served = false;

  @override
  Clock get clock => _r.clock;

  void _live() {
    if (_disposed) throw StateError('participant $who is gone');
  }

  H _keep<H extends IHandle>(H h) {
    _handles.add(h);
    return h;
  }

  /// A handle doing [withdraw], kept until it is disposed.
  IHandle _keepDoing(void Function() withdraw) {
    late final _Disposer d;
    d = _Disposer(() {
      _handles.remove(d);
      withdraw();
    });
    return _keep(d);
  }

  /// Whether [name] is in its vocabularies.
  bool owns(String name) =>
      vocabularies.any((ns) => name == ns || name.startsWith('$ns.'));

  void _mayDefine(Descriptor d) {
    _live();
    if (!owns(d.name)) {
      throw NotPermitted(
        '$who defines in ${vocabularies.isEmpty ? 'no vocabulary' : vocabularies.join(', ')}, not ${d.name}',
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
      return cause.withBy(who);
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
  /// in the same vocabularies, with the same rights and access; what it
  /// defines and does is told as its own, and its guards judge its own
  /// commands. One part per name; it goes with this one.
  @override
  LocalParticipant child(String name) {
    _live();
    return _children[name] ??= LocalParticipant._(
      _r,
      who.child(name),
      vocabularies,
      rights,
      access,
      parent: this,
    );
  }

  // --- Reading and calling, as [who] --------------------------------------

  @override
  Object? read(String state, {String? key}) => _view.read(state, key: key);

  @override
  T? readAs<T>(String state, Shape<T> shape, {String? key}) =>
      _view.readAs(state, shape, key: key);

  @override
  Map<String?, Object?> readAll(String state) => _view.readAll(state);

  @override
  Future<Map<String?, Object?>> fetch(String state, {bool keep = true}) =>
      _view.fetch(state, keep: keep);

  @override
  Future<Map<String, Object?>> describe() async => _r.describeFor(who);

  @override
  Future<Explanation> explain(String state, {String? key}) async {
    if (!_r.mayRead(who, state)) throw NotPermitted('$who may not read $state');
    _r.usedBy(state, who);
    return _r.explain(state, key: key);
  }

  @override
  Stream<void> get catalogChanges => _r.catalogChanges.map((_) {});

  @override
  Stream<Object?> watch(String state, {String? key}) =>
      _r.mayRead(who, state) ? _r.watch(state, key: key) : Stream.value(null);

  @override
  Stream<T?> watchAs<T>(String state, Shape<T> shape, {String? key}) =>
      _r.mayRead(who, state)
      ? _r.watchAs(state, shape, key: key)
      : Stream.value(null);

  @override
  Stream<void> changes(Set<String> states) => _view.changes(states);

  @override
  Stream<FactMessage> facts(String fact) => _view.facts(fact);

  @override
  Stream<(T, FactMessage)> factsAs<T>(String fact, Shape<T> shape) =>
      _view.factsAs(fact, shape);

  @override
  Future<List<FactMessage>> recent(String fact, int count) =>
      _view.recent(fact, count);

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
    bool override = false,
  }) {
    _live();
    final c = _as(cause);
    return _r.call(
      command,
      params,
      by: who,
      id: id,
      cause: c,
      override: override,
    );
  }

  @override
  bool get synced => true;

  @override
  WordStatus status(String word) => _view.status(word);

  @override
  Stream<WordStatus> statusChanges(String word) => _view.statusChanges(word);

  // --- Its own words ------------------------------------------------------

  @override
  IStateHandle defineState(StateDescriptor d, {Shape<Object?>? shape}) {
    _mayDefine(d);
    return _keep(
      _OwnState(this, _r.defineState(access.state(d), by: who, shape: shape)),
    );
  }

  @override
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
  }) {
    _mayDefine(d);
    final h = _r.defineCommand(d, handler, available: available);
    _commands.add(d.name);
    return _keepDoing(() {
      _commands.remove(d.name);
      h.dispose();
    });
  }

  @override
  IHandle defineQuery(
    QueryDescriptor d,
    CommandHandler handler, {
    Availability? available,
  }) {
    _mayDefine(d);
    final h = _r.defineQuery(d, handler, available: available);
    _commands.add(d.name);
    return _keepDoing(() {
      _commands.remove(d.name);
      h.dispose();
    });
  }

  @override
  IFactHandle defineFact(FactDescriptor d, {Shape<Object?>? shape}) {
    _mayDefine(d);
    return _keep(
      _OwnFact(this, _r.defineFact(access.fact(d), by: who, shape: shape)),
    );
  }

  @override
  IFactHandle producer(String fact, {Shape<Object?>? shape}) {
    _live();
    final check = rights.produce;
    if ((check == null ? '$who may produce nothing' : check(who, fact))
        case final why?) {
      throw NotPermitted(why);
    }
    return _keep(_OwnFact(this, _r.producer(fact, by: who, shape: shape)));
  }

  /// The id the registry knows its guard [id] by: `<who>#<id>`, so two
  /// participants' guards of one id are two guards, and a refusal says
  /// whose it was.
  String guardId(String id) => '${who.selector}#$id';

  /// Whether its guards judge calls of [command]: one it, or a part of
  /// it, defined.
  bool _judges(String command) =>
      _commands.contains(command) ||
      _children.values.any((c) => c._judges(command));

  @override
  IHandle addGuard(String id, GuardCheck check, {bool overridable = true}) {
    _live();
    return _keepDoing(
      _r
          .addGuard(
            guardId(id),
            (c) => _judges(c.command.name) ? check(c) : null,
            overridable: overridable,
          )
          .dispose,
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
    return _keepDoing(
      _r
          .addAskedGuard(
            guardId(id),
            (c) async => _judges(c.command.name) ? ask(c) : null,
            overridable: overridable,
            timeout: timeout,
          )
          .dispose,
    );
  }

  @override
  void availabilityChanged(String command) {
    _live();
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
    return _keepDoing(() {
      _kinds.remove(kind.name);
      h.dispose();
    });
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
  Future<void> settle() async {}

  late final OwnerGroup _group = OwnerGroup(this);

  @override
  void attach(Map<String, Owner> owners) {
    _live();
    _group.attach(owners);
  }

  @override
  void sync() => _group.sync();

  @override
  void dispose() {
    if (_disposed) return;
    _group.dispose();
    _disposed = true;
    for (final c in [..._children.values].reversed) {
      c.dispose();
    }
    for (final h in [..._handles].reversed) {
      h.dispose();
    }
    _handles.clear();
    if (parent case final p?) {
      p._children.removeWhere((_, c) => c == this);
      return;
    }
    final taken = _taken[_r];
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
  Shape<Object?>? get shape => _raw.shape;

  @override
  void set(Object? value, {String? key, Cause? cause}) =>
      _raw.set(value, key: key, cause: _p._as(cause));

  @override
  void remove({String? key, Cause? cause}) =>
      _raw.remove(key: key, cause: _p._as(cause));

  @override
  void dispose() {
    _p._handles.remove(this);
    _raw.dispose();
  }
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
  Shape<Object?>? get shape => _raw.shape;

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
  void dispose() {
    _p._handles.remove(this);
    _raw.dispose();
  }
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
