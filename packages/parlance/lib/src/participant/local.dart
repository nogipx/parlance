import 'package:clock/clock.dart' show Clock;

import '../registry/cause.dart';
import 'serving.dart';
import '../registry/compat.dart';
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
  /// A participant speaking as [who], with its [owners] attached (SPEC
  /// §22.1, §22.3), each speaking as the part named by its vocabulary.
  /// It defines words only in its owners' vocabularies and in
  /// [vocabularies]: those whose owners are not here (a guest's, served
  /// across a connection) or whose words come at run time (`WordSet.open`).
  /// A word is named in its vocabulary: `orders.cancel` is in `orders`. A
  /// vocabulary is one participant's, and one owner's: one given twice, or
  /// that another live participant has, is refused. When an owner cannot
  /// define its words, the participant goes and the error goes on.
  LocalParticipant participant(
    Principal who, {
    Iterable<IOwner> owners = const [],
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
  }) {
    who.check();
    access.readers?.check();
    access.callers?.check();
    final attached = [...owners];
    // Each owner's vocabulary, unless said already: two owners of one are
    // refused as they attach.
    final said = {for (final v in vocabularies) v.name};
    vocabularies = [
      ...vocabularies,
      for (final o in attached)
        if (wordsOf(o) case final w? when said.add(w.name)) w,
    ];
    for (final v in vocabularies) {
      v.check();
    }
    final given = [for (final v in vocabularies) v.name];
    for (final (i, a) in given.indexed) {
      if (given.skip(i + 1).contains(a)) {
        throw ArgumentError.value(
          vocabularies,
          'vocabularies',
          'the vocabulary $a is given twice',
        );
      }
    }
    final names = given.toSet();
    final taken = _taken[this] ??= {};
    // A session of the same principal holding them is one whose
    // connection went and was not seen to (a link half open, its host
    // told late): a new session of the part takes its place, as an MQTT
    // broker takes a client's session over (SPEC §14). Another
    // principal's is refused below.
    for (final old in {
      for (final ns in names)
        if (taken[ns] case final p? when p.who == who && p._end != null) p,
    }) {
      old._end!();
    }
    for (final ns in names) {
      checkVocabularyName(ns);
      if (taken[ns] case final p?) {
        throw NotPermitted('vocabulary $ns is ${p.who}\'s');
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
    _aliveIn(this).add(p);
    if (attached.isNotEmpty) {
      try {
        p._group.attach(attached);
      } catch (_) {
        p.dispose();
        rethrow;
      }
    }
    return p;
  }
}

/// The participants of each registry not disposed yet, in the order they
/// were made: what its `dispose` ends first, a served one by its session.
final Expando<Set<LocalParticipant>> _alive = Expando('alive');

Set<LocalParticipant> _aliveIn(Registry r) => _alive[r] ??= () {
  final alive = <LocalParticipant>{};
  r.beforeDispose(() {
    for (final p in [...alive].reversed) {
      (p._end ?? p.dispose)();
    }
  });
  return alive;
}();

/// The vocabularies taken, by name, and whose they are.
final Expando<Map<String, LocalParticipant>> _taken = Expando();

/// A participant of a registry in this process: the registry as [who] may
/// use it.
/// The registry [p] speaks to: the package's own, for a session that
/// serves [p] across a connection (`serve`); not exported, so a part given
/// a participant never holds the registry.
Registry registryOf(LocalParticipant p) => p._r;

/// [p]'s code, or the participant's across a connection that [p] stands
/// for, was built against [schemas] (SPEC §6.9): held until [p] goes.
void builtAgainstSchemas(
  LocalParticipant p,
  Map<String, Object?> schemas, {
  String? from,
}) => p._builtAgainst(schemas, from);

/// What [p] was told it was built against, let go: the participant across
/// a connection it stands for went, though its session stays.
void forgetBuiltAgainst(LocalParticipant p) => p._forgetBuilt();

/// Takes [p] for a session to serve (`serve`): one participant, one
/// session, and only a new one, so the session owns all it has. Refused
/// for one served already, or one that did anything here: its words,
/// guards, choices, owners or parts would go with the session. [end] ends
/// the session, when a new one of the same principal takes its place
/// ([Participants.participant]). Not exported.
void takeForServing(LocalParticipant p, {required void Function() end}) {
  p._live();
  if (p._served) throw StateError('${p.who} is served already');
  if (p._group.owners.isNotEmpty) {
    throw StateError(
      '${p.who} has owners here: a participant served has its owners at the '
      'other end, its vocabularies granted (host.participant(who, '
      'vocabularies: [...]).serve(endpoint))',
    );
  }
  if (p._handles.isNotEmpty || p._children.isNotEmpty) {
    throw StateError(
      '${p.who} did things in this process: serve a participant made for '
      'the session',
    );
  }
  p._served = true;
  p._end = end;
}

final class LocalParticipant implements IRawParticipant {
  LocalParticipant._(
    this._r,
    this.who,
    this.vocabularyNames,
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
  final Set<String> vocabularyNames;

  /// What it may do beyond defining in its vocabularies.
  final ParticipantRights rights;

  /// What it defined, registered and added, to withdraw on [dispose]: each
  /// leaves it when withdrawn on its own.
  final Set<IHandle> _handles = {};

  /// The commands it defined: its guards judge their calls only.
  final Set<String> _commands = {};

  /// Its commands and queries with an availability check.
  final Set<String> _checked = {};

  /// The names of the choices it gives.
  final Set<String> _choices = {};
  bool _disposed = false;
  bool _served = false;

  /// Ends the session that serves it; null while none does.
  void Function()? _end;

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
    late final Disposer d;
    d = Disposer(() {
      _handles.remove(d);
      withdraw();
    });
    return _keep(d);
  }

  /// Whether [name] is in its vocabularies.
  bool owns(String name) =>
      vocabularyNames.any((ns) => name == ns || name.startsWith('$ns.'));

  void _mayDefine(Descriptor d) {
    _live();
    if (!owns(d.name)) {
      throw NotPermitted(
        '$who defines in ${vocabularyNames.isEmpty ? 'no vocabulary' : vocabularyNames.join(', ')}, not ${d.name}',
      );
    }
    if (rights.define?.call(defineCallOf(who, d)) case final why?) {
      throw NotPermitted(why);
    }
  }

  /// [cause], or its own: what it writes and calls is its own act, or
  /// follows from a call it serves (`call.causeFor(who)`). A part takes a
  /// cause of a whole it is part of as its own: what it does is its own.
  Cause _as(Cause? cause) {
    // In a handler, what it does follows from the call it serves.
    if (cause == null) return inReplyAs(who) ?? Cause(who);
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
  IRawParticipant get whole => parent ?? this;

  @override
  LocalParticipant child(String name) {
    _live();
    return _children[name] ??= LocalParticipant._(
      _r,
      who.child(name),
      vocabularyNames,
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
  }) {
    _live();
    final c = _as(cause);
    return _r.call(command, params, by: who, id: id, cause: c);
  }

  @override
  Future<CallResult<Object?>> callAs(
    String command,
    Object? params,
    Shape<Object?> shape, {
    String? id,
    Cause? cause,
  }) {
    _live();
    return _r.callKept(
      command,
      Kept(params, shape),
      by: who,
      id: id,
      cause: _as(cause),
    );
  }

  @override
  bool get synced => true;

  @override
  WordStatus status(String word) => _view.status(word);

  @override
  Stream<WordStatus> statusChanges(String word) => _view.statusChanges(word);

  @override
  Descriptor? descriptor(String word) => _view.descriptor(word);

  /// Each word told once as it was built against it, held until it goes.
  @override
  void builtAgainst(Iterable<IWord> words, {String? from}) =>
      _builtAgainst(schemasOf(words), from);

  /// What it told the registry it was built against, by word: the
  /// schema's fingerprint and the package it came from.
  final Map<String, (String, String?)> _built = {};
  final List<IHandle> _builtHandles = [];

  void _builtAgainst(Map<String, Object?> schemas, String? from) {
    if (_disposed) return;
    final told = {
      for (final MapEntry(:key, :value) in schemas.entries)
        if (_built[key] != (fingerprintOf(value), from)) key: value,
    };
    if (told.isEmpty) return;
    for (final MapEntry(:key, :value) in told.entries) {
      _built[key] = (fingerprintOf(value), from);
    }
    _builtHandles.add(_r.builtAgainst(who, told, from: from));
  }

  void _forgetBuilt() {
    for (final h in _builtHandles) {
      h.dispose();
    }
    _builtHandles.clear();
    _built.clear();
  }

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
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) {
    _mayDefine(d);
    final h = _r.defineCommand(
      d,
      serving(handler),
      available: available,
      params: params,
      returns: returns,
    );
    _commands.add(d.name);
    if (available != null) _checked.add(d.name);
    return _keepDoing(() {
      _commands.remove(d.name);
      _checked.remove(d.name);
      h.dispose();
    });
  }

  @override
  IHandle defineQuery(
    QueryDescriptor d,
    CommandHandler handler, {
    Availability? available,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) {
    _mayDefine(d);
    final h = _r.defineQuery(
      d,
      serving(handler),
      available: available,
      params: params,
      returns: returns,
    );
    _commands.add(d.name);
    if (available != null) _checked.add(d.name);
    return _keepDoing(() {
      _commands.remove(d.name);
      _checked.remove(d.name);
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
  IHandle addGuard(String id, GuardCheck check) {
    _live();
    return _keepDoing(
      _r
          .addGuard(
            guardId(id),
            (c) => _judges(c.command.name) ? check(c) : null,
          )
          .dispose,
    );
  }

  /// A guard of its own whose check it makes across a connection (SPEC
  /// §22.4): the host's side of a remote participant's guard.
  IHandle addAskedGuard(
    String id,
    Future<String?> Function(PendingCall call) ask, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    _live();
    return _keepDoing(
      _r
          .addAskedGuard(guardId(id), ask, timeout: timeout, judges: _judges)
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
  void availabilityMayHaveChanged() {
    if (_disposed) return;
    for (final c in _checked) {
      _r.availabilityChanged(c);
    }
  }

  @override
  IHandle addChoices(Choices choices) {
    _live();
    final h = _r.addChoices(choices);
    _choices.add(choices.name);
    return _keepDoing(() {
      _choices.remove(choices.name);
      h.dispose();
    });
  }

  @override
  void choicesChanged(String name) {
    if (!_choices.contains(name)) {
      throw NotPermitted('$who gives no choices of $name');
    }
    _r.choicesChanged(name);
  }

  @override
  void batch(void Function() writes) => _r.batch(writes);

  @override
  Future<void> settle() => OwnerGroup.idle();

  late final OwnerGroup _group = OwnerGroup(this);

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
    _forgetBuilt();
    if (parent case final p?) {
      p._children.removeWhere((_, c) => c == this);
      return;
    }
    final taken = _taken[_r];
    taken?.removeWhere((_, p) => p == this);
    _alive[_r]?.remove(this);
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

  // What a participant gone writes is not written: code still running
  // when it went (an await answered after) is let go quietly.
  @override
  void set(Object? value, {String? key, Cause? cause}) {
    if (_p._disposed) return;
    _raw.set(value, key: key, cause: _p._as(cause));
  }

  @override
  void remove({String? key, Cause? cause}) {
    if (_p._disposed) return;
    _raw.remove(key: key, cause: _p._as(cause));
  }

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
    if (p._disposed) return false;
    if (cause != null && cause.by != p.who && !p._wholeOf(cause.by)) {
      final check = p.rights.speakFor;
      if ((check == null
              ? '${p.who} may speak for no one'
              : check(speakForCallOf(p.who, cause.by, descriptor.name)))
          case final why?) {
        throw NotPermitted(why);
      }
    }
    cause ??= inReplyAs(p.who);
    final own = cause == null || cause.by == p.who || p._wholeOf(cause.by);
    return _raw.emit(payload, id: id, cause: own ? p._as(cause) : cause);
  }

  @override
  void dispose() {
    _p._handles.remove(this);
    _raw.dispose();
  }
}
