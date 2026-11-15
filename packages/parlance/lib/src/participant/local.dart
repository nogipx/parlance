// Internal to the library: what these files show is not a promise
// Documented surface lives in schema.dart and app.dart.
// ignore_for_file: public_member_api_docs
import 'package:clock/clock.dart' show Clock;

import '../registry/address.dart';
import '../registry/cause.dart';
import 'serving.dart';
import '../registry/compat.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/json.dart' show jsonEquals;
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/shapes.dart';
import '../registry/words.dart';
import '../registry/streams.dart';
import '../view/view.dart';
import 'owner.dart';
import 'participant.dart';

/// Participants of a registry in this process (SPEC §22.1).
extension Participants on Registry {
  /// A participant speaking as [who], with its [owners] attached (SPEC
  /// §22.1, §22.3), each speaking as [who] of it, named by its vocabulary.
  /// It defines words only in its owners' vocabularies and in
  /// [vocabularies]: those whose owners are not here (a guest's, served
  /// across a connection) or whose words come at run time (`WordSet.open`).
  /// A word is named in its vocabulary: `orders.cancel` is in `orders`. A
  /// vocabulary has one participant and one owner per whole principal: one
  /// given twice, or held by another participant of that principal, is refused. When an owner cannot
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
    // broker takes a client's session over (SPEC §14). Taken over only
    // once its vocabularies are free of others: a refusal leaves the old
    // as it was. An owner that cannot define its words fails after.
    bool takesOver(LocalParticipant p) => p.who == who && p._end != null;
    for (final ns in names) {
      checkVocabularyName(ns);
      if (taken[(who.whole, ns)] case final p? when !takesOver(p)) {
        throw NotPermitted('vocabulary $ns is ${p.who}\'s');
      }
    }
    for (final old in {
      for (final ns in names)
        if (taken[(who.whole, ns)] case final p? when takesOver(p)) p,
    }) {
      old._end!('a new session of $who took its place', tell: true);
    }
    final p = LocalParticipant._(
      this,
      who,
      Set.unmodifiable(names),
      rights,
      access,
    );
    for (final ns in names) {
      taken[(who.whole, ns)] = p;
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
      if (p._end case final end?) {
        end('the host ended', tell: false);
      } else {
        p.dispose();
      }
    }
  });
  return alive;
}();

/// The vocabularies taken, by name, and whose they are.
final Expando<Map<(Principal, String), LocalParticipant>> _taken = Expando();

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

/// Ends a session for [why]; [tell]: the part across is told, and does
/// not join again.
typedef EndSession = void Function(String why, {required bool tell});

/// Takes [p] for a session to serve (`serve`): one participant, one
/// session, and only a new one, so the session owns all it has. Refused
/// for one served already, or one that did anything here: its words,
/// guards or owners would go with the session. [end] ends
/// the session, when a new one of the same principal takes its place
/// ([Participants.participant]). Not exported.
void takeForServing(LocalParticipant p, {required EndSession end}) {
  mayServe(p);
  p._served = true;
  p._end = end;
}

/// Refuses ([StateError]) to serve [p] when [takeForServing] would, taking
/// nothing: what a session checks before it registers on its endpoint.
void mayServe(LocalParticipant p) {
  p._live();
  if (p._served) throw StateError('${p.who} is served already');
  if (p._group.owners.isNotEmpty) {
    throw StateError(
      '${p.who} has owners here: a participant served has its owners at the '
      'other end, its vocabularies granted (host.serve(who, endpoint, '
      'vocabularies: [...]))',
    );
  }
  if (p._handles.isNotEmpty || p._ofOwners.isNotEmpty) {
    throw StateError(
      '${p.who} did things in this process: serve a participant made for '
      'the session',
    );
  }
}

final class LocalParticipant implements IRawParticipant {
  LocalParticipant._(
    this._r,
    this.who,
    this.vocabularyNames,
    this.rights,
    this.access, {
    LocalParticipant? parent,
  }) : _whole = parent,
       _view = LocalView(_r, by: who, cause: () => inReplyAs(who));

  /// The participant this one speaks for an owner of ([ofOwner]); null
  /// for the whole.
  final LocalParticipant? _whole;

  final Map<String, LocalParticipant> _ofOwners = {};

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

  /// Its commands and queries with a whyNot.
  final Set<String> _checked = {};

  bool _disposed = false;
  bool _served = false;

  /// Ends the session that serves it; null while none does.
  EndSession? _end;

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
  bool owns(String name) {
    if (name.contains('/')) {
      final address = WordAddress.parse(name);
      if (address.target != who.whole) return false;
      name = address.word;
    }
    return vocabularyNames.any((ns) => name == ns || name.startsWith('$ns.'));
  }

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
  /// follows from a call it serves (`call.causeFor(who)`). One of an owner
  /// takes a cause of its whole as its own: what it does is its own.
  Cause _as(Cause? cause) {
    // In a handler, what it does follows from the call it serves.
    if (cause == null) return inReplyAs(who) ?? Cause(who);
    if (cause.by == who) return cause;
    if (_wholeOf(cause.by)) {
      return cause.withBy(who);
    }
    throw NotPermitted('$who acts as itself, not as ${cause.by}');
  }

  /// Whether [p] is the whole this one speaks for an owner of.
  bool _wholeOf(Principal p) {
    for (var w = _whole; w != null; w = w._whole) {
      if (w.who == p) return true;
    }
    return false;
  }

  @override
  IRawParticipant get whole => _whole ?? this;

  /// It for its owner [name] (SPEC §22.3): it speaks as `who.ofOwner(name)`
  /// in the same vocabularies, with the same rights and access; what it
  /// defines and does is told as that owner's, and its guards judge its
  /// own commands. One per name; it goes with this one.
  @override
  LocalParticipant ofOwner(String name) {
    _live();
    return _ofOwners[name] ??= LocalParticipant._(
      _r,
      who.ofOwner(name),
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
  Map<String?, T> readAllAs<T>(String state, Shape<T> shape) =>
      _view.readAllAs(state, shape);

  @override
  Future<Map<String?, Object?>> fetch(String state, {bool keep = true}) =>
      _view.fetch(state, keep: keep);

  @override
  Future<Map<String, Object?>> describe() async => _r.describeFor(who);

  @override
  Future<Explanation> explain(
    String state, {
    String? key,
    int historyCount = 0,
  }) async {
    if (!_r.checkRead(who, state, cause: inReplyAs(who))) {
      throw NotPermitted('$who may not read $state');
    }
    _r.usedBy(state, who);
    return _r.explain(state, key: key, by: who, historyCount: historyCount);
  }

  @override
  Future<Map<String, Object?>> inspectCall(String id) async {
    try {
      return _r.inspectCall(id, by: who);
    } on StateError catch (e) {
      throw NotPermitted(e.message);
    }
  }

  @override
  int accessRevision(String word) => _r.accessRevision(word);

  @override
  Stream<void> get catalogChanges => _r.catalogChanges.map((_) {});

  @override
  Stream<Object?> watch(String state, {String? key}) =>
      _watchState<Object?>(state, () => _r.read(state, key: key), jsonEquals);

  Stream<T?> _watchState<T>(
    String state,
    T? Function() read,
    bool Function(T?, T?) equal,
  ) {
    T? current() => _r.mayRead(who, state) ? read() : null;
    return Stream<(int, T?)>.multi((out) {
          void tell() => out.add((_r.accessRevision(state), current()));
          final sub = _view
              .changes({state})
              .listen((_) => tell(), onError: out.addError, onDone: out.close);
          tell();
          out.onPause = sub.pause;
          out.onResume = sub.resume;
          out.onCancel = sub.cancel;
        })
        .map(
          (event) =>
              event.$1 == _r.accessRevision(state) && _r.mayRead(who, state)
              ? event.$2
              : current(),
        )
        .distinct(equal);
  }

  @override
  Stream<T?> watchAs<T>(String state, Shape<T> shape, {String? key}) =>
      _watchState<T>(
        state,
        () => _r.readAs(state, shape, key: key),
        (a, b) => a == null || b == null ? a == b : shape.equals(a, b),
      );

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
    CancellationToken? cancel,
  }) {
    _live();
    final c = _as(cause);
    return _r
        .call(
          command,
          params,
          by: who,
          id: id == null ? null : '${who.whole.selector}#$id',
          cause: c,
          cancel: cancel,
        )
        .then((r) => id != null && r is CallLost ? CallLost(id, r.how) : r);
  }

  @override
  Future<CallResult<Object?>> callAs(
    String command,
    Object? params,
    Shape<Object?> shape, {
    String? id,
    Cause? cause,
    CancellationToken? cancel,
  }) {
    _live();
    return _r
        .callKept(
          command,
          Kept(params, shape),
          by: who,
          id: id == null ? null : '${who.whole.selector}#$id',
          cause: _as(cause),
          cancel: cancel,
        )
        .then((r) => id != null && r is CallLost ? CallLost(id, r.how) : r);
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
  void builtAgainst(Iterable<IWord> words, {String? from, Principal? target}) =>
      _builtAgainst({
        for (final w in words)
          (target == null ? w.name : WordAddress(target, w.name).toString()):
              schemaOfWord(w),
      }, from);

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
  Stream<T> openStream<T>(
    String name,
    Object? params,
    Shape<Object?> paramsShape,
    Shape<T> itemShape, {
    CancellationToken? cancel,
    Stream<Object?>? input,
    Shape<Object?>? inputShape,
    String kind = 'serverStream',
  }) => LazyDataStream(() {
    if (_disposed) {
      throw const StreamFailure(
        StreamFailureCode.unavailable,
        'the participant ended',
      );
    }
    final lease = StreamLease();
    final handle = _keepDoing(
      () => lease.end(
        const StreamFailure(
          StreamFailureCode.unavailable,
          'the participant ended',
        ),
      ),
    );
    return _r.openStream(
      name,
      Kept(params, paramsShape),
      itemShape,
      by: who,
      cause: _as(null),
      cancel: cancel,
      input: input,
      inputShape: inputShape,
      kind: kind,
      lifetime: lease,
      onClosed: () => _handles.remove(handle),
    );
  });

  @override
  IHandle defineStream(
    DataStreamDescriptor d,
    StreamHandler handler, {
    WhyNot? whyNot,
    Shape<Object?>? params,
    Shape<Object?>? item,
    Shape<Object?>? input,
  }) {
    d = d.atTarget(who) as DataStreamDescriptor;
    _mayDefine(d);
    final h = _r.defineStream(
      access.dataStream(d),
      (call) => contextualStream(handler, call),
      whyNot: whyNot,
      params: params,
      item: item,
      input: input,
    );
    _checked.add(d.name);
    _streams.add(d.name);
    return _keepDoing(() {
      _checked.remove(d.name);
      _streams.remove(d.name);
      h.dispose();
    });
  }

  final Set<String> _streams = {};

  @override
  IStateHandle defineState(StateDescriptor d, {Shape<Object?>? shape}) {
    d = d.atTarget(who) as StateDescriptor;
    _mayDefine(d);
    return _keep(
      _OwnState(this, _r.defineState(access.state(d), by: who, shape: shape)),
    );
  }

  @override
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    WhyNot? whyNot,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) {
    d = d.atTarget(who) as CommandDescriptor;
    _mayDefine(d);
    final h = _r.defineCommand(
      d,
      serving(handler),
      whyNot: whyNot,
      params: params,
      returns: returns,
    );
    _commands.add(d.name);
    if (whyNot != null) _checked.add(d.name);
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
    WhyNot? whyNot,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) {
    d = d.atTarget(who) as QueryDescriptor;
    _mayDefine(d);
    final h = _r.defineQuery(
      d,
      serving(handler),
      whyNot: whyNot,
      params: params,
      returns: returns,
    );
    _commands.add(d.name);
    if (whyNot != null) _checked.add(d.name);
    return _keepDoing(() {
      _commands.remove(d.name);
      _checked.remove(d.name);
      h.dispose();
    });
  }

  @override
  IFactHandle defineFact(FactDescriptor d, {Shape<Object?>? shape}) {
    d = d.atTarget(who) as FactDescriptor;
    _mayDefine(d);
    return _keep(
      _OwnFact(this, _r.defineFact(access.fact(d), by: who, shape: shape)),
    );
  }

  /// The id the registry knows its guard [id] by: `<who>#<id>`, so two
  /// participants' guards of one id are two guards, and a refusal says
  /// whose it was.
  String guardId(String id) => '${who.selector}#$id';

  /// Whether its guards judge calls of [command]: one it, or it for one of
  /// its owners, defined.
  bool _judges(String command) =>
      _commands.contains(command) ||
      _ofOwners.values.any((c) => c._judges(command));

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
  void whyNotChanged(String command) {
    _live();
    if (!_commands.contains(command) && !_streams.contains(command)) {
      throw NotPermitted('$command is not $who\'s command');
    }
    _r.whyNotChanged(command);
  }

  @override
  void whyNotMayHaveChanged() {
    if (_disposed) return;
    for (final c in _checked) {
      _r.whyNotChanged(c);
    }
  }

  @override
  void batch(void Function() writes) => undoingOnThrow(() => _r.batch(writes));

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
    for (final c in [..._ofOwners.values].reversed) {
      c.dispose();
    }
    for (final h in [..._handles].reversed) {
      h.dispose();
    }
    _handles.clear();
    _forgetBuilt();
    if (_whole case final p?) {
      p._ofOwners.removeWhere((_, c) => c == this);
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
  final RawFactSayer _raw;

  @override
  FactDescriptor get descriptor => _raw.descriptor;

  @override
  Shape<Object?>? get shape => _raw.shape;

  @override
  bool say(Object? payload, {String? id, Cause? cause}) {
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
    return _raw.say(
      payload,
      id: '${descriptor.name}#${id ?? newId()}',
      cause: own ? p._as(cause) : cause,
    );
  }

  @override
  void dispose() {
    _p._handles.remove(this);
    _raw.dispose();
  }
}
