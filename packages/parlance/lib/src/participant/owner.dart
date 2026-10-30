import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart' as clock_;

import '../registry/cause.dart' show Principal;
import '../registry/descriptors.dart';
import '../registry/registry.dart';
import '../registry/words.dart' show ICommandWord, IFactOf, Keyed, WordSet;
import 'serving.dart';
import 'serving.dart' as serving_ show apart, once;
import 'participant.dart';

/// Handles to withdraw together: what an owner put in a registry.
final class Handles implements IHandle {
  final List<IHandle> _all = [];
  bool _disposed = false;

  /// Keeps [h] to withdraw with the rest, and gives it back as it is:
  /// `_mode = handles.keep(p.state(Mode.word).define());`
  H keep<H extends IHandle>(H h) {
    if (_disposed) {
      h.dispose();
      throw StateError('these handles were withdrawn');
    }
    _all.add(h);
    return h;
  }

  /// Withdraws them, the last kept first; a second call does nothing.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final h in _all.reversed) {
      h.dispose();
    }
    _all.clear();
  }
}

/// An owner of words (SPEC §6, §19, §23.4): what `main` gives a
/// participant it makes (`host.participant(who, owners: [Home(...)])`),
/// to speak as the part named by its vocabulary (`home@house`; one of no
/// words, as the participant itself); who that is, and what it may,
/// `main` says, never the owner.
///
/// It has no members: what an owner does with the library it does by
/// [OwnerTools], extensions, so no name of an owner's own is the
/// library's, in this version or one to come. A base the generator made
/// implements it, and the owner extends that base.
abstract interface class IOwner {
  /// Called by an owner in its constructor (a base the generator made
  /// does it): [define] defines its words once it is attached, through the
  /// participant it is given, and they go when the owner goes; [write],
  /// when given, writes what it set before it was attached, first of each
  /// sync. [words] is the vocabulary its words are in: it speaks as the
  /// part of its name; without, it defines none and speaks as the
  /// participant.
  static void made(
    IOwner owner, {
    required void Function(IParticipant p) define,
    void Function()? write,
    WordSet? words,
  }) {
    final c = _Core.of(owner);
    c.define = define;
    c.write = write;
    c.words = words;
  }
}

/// What the library keeps of an owner, beside it: an owner holds none of
/// it, so none of its names is the owner's.
final class _Core {
  _Core(this.type);

  static final Expando<_Core> _all = Expando('owner');
  static _Core of(IOwner o) => _all[o] ??= _Core(o.runtimeType);

  /// The owners of each participant or part attached: told when a
  /// handler there answered.
  static final Expando<List<_Core>> _ofPart = Expando('owners of a part');

  final Type type;

  /// The vocabulary its words are in, when its base said it: held to the
  /// participant's before anything is defined, and the name of the part
  /// it speaks as.
  WordSet? words;
  final Handles handles = Handles();
  IParticipant? participant;
  OwnerGroup? group;
  void Function(IParticipant p)? define;
  void Function()? write;
  final List<void Function()> follows = [];
  final List<_Choices> choices = [];

  /// Its keyed states, by the kind of their keys.
  final Map<String, List<Keyed<Object?>>> keyed = {};

  /// What waits for it to be attached, in order; null once it is.
  List<void Function(IParticipant p)>? _due = [];

  /// Whether it was synced once, after it was attached.
  bool synced = false;

  void whenAttached(void Function(IParticipant p) f) {
    if (participant case final p? when _due == null) {
      f(p);
    } else {
      _due!.add(f);
    }
  }

  void attach(IParticipant p, OwnerGroup group) {
    if (participant != null) throw StateError('$type is attached');
    _mayOwn(p);
    participant = p;
    this.group = group;
    (_ofPart[p] ??= []).add(this);
    runZoned(
      () => define?.call(p),
      zoneValues: {
        keyedDefined: (String kind, Keyed<Object?> k) =>
            (keyed[kind] ??= []).add(k),
      },
    );
    for (final c in choices) {
      c.attach(p, this);
    }
    final due = _due!;
    _due = null;
    for (final f in due) {
      f(p);
    }
  }

  /// Refuses [p] when its vocabularies leave out the one its words are
  /// in, saying what to give and where: a vocabulary is a right, given
  /// where the participant is made, never taken by attaching an owner.
  void _mayOwn(IParticipant p) {
    final w = words;
    if (w == null) return;
    final raw = p.raw;
    final given = raw.vocabularies;
    if (given.contains(w.name)) return;
    final whole = raw.whole.who;
    throw NotPermitted(
      '$type, attached as ${p.who}, owns the words of the vocabulary '
      '${w.name}, but the host did not grant its participant $whole that '
      'vocabulary (it has ${given.isEmpty ? 'none' : given.join(', ')}). '
      'The host grants it where it serves the participant: '
      'host.participant($whole, vocabularies: '
      '[${w.dartName ?? 'the WordSet of ${w.name}'}]).serve(endpoint)',
    );
  }

  /// [signal] tells it to be synced, once for all told in one turn.
  void syncOn(Stream<void> signal) => whenAttached(
    (_) =>
        handles.keep(_Listening(signal.listen((_) => group?._changed(this)))),
  );

  void sync() {
    write?.call();
    for (final f in [...follows]) {
      f();
    }
    synced = true;
    _relist();
    moved();
  }

  /// Lists its choices again: those that changed are told, and what went
  /// of them goes of its keyed states keyed by their kind.
  void _relist() {
    for (final c in choices) {
      for (final id in c.relist()) {
        for (final k in keyed[c.kind] ?? const <Keyed<Object?>>[]) {
          if (k.keys.contains(id)) k.remove(id);
        }
      }
    }
  }

  bool _movedDue = false;

  /// What it keeps elsewhere may have moved (a handler answered, it heard
  /// something, it followed its model): its choices are listed again and
  /// its commands' checks asked again, once in a turn, and what changed
  /// told. No owner says so itself.
  void moved() {
    if (_movedDue || participant == null) return;
    _movedDue = true;
    scheduleMicrotask(() {
      _movedDue = false;
      final p = participant;
      if (group == null || p == null) return;
      if (choices.isNotEmpty) p.batch(_relist);
      p.raw.availabilityMayHaveChanged();
    });
  }

  void dispose() {
    handles.dispose();
    group?._left(this);
    group = null;
    if (participant case final p?) {
      _ofPart[p]?.remove(this);
      // What it defined through its part goes with it; one of no words
      // speaks as the participant, which is not its to end.
      if (words != null) p.dispose();
    }
  }
}

/// What an owner does with the library (SPEC §19, §23.4): written in it as
/// its own, `listen(...)`, `caller`; a name the owner has of its own is
/// its own, and one these tools have is reached as `OwnerTools(this).x`.
/// An owner's participant itself, for tools (`tools.dart`): what an owner
/// does by name or with words named at run time, through `p.raw`. An app's
/// owner needs none of it: its base, its tools and the clients it makes
/// (`HouseClient.of(this)`) reach the participant for it.
extension OwnerParticipant on IOwner {
  /// The participant it speaks through: the part named by its vocabulary.
  /// Throws while it is not attached: what needs it waits in
  /// [whenAttached].
  IParticipant get participant =>
      _Core.of(this).participant ??
      (throw StateError('$runtimeType is not attached'));

  /// Runs [f] with its participant once it is attached, after its words
  /// are defined; at once, when it is.
  void whenAttached(void Function(IParticipant p) f) =>
      _Core.of(this).whenAttached(f);
}

extension OwnerTools on IOwner {
  /// Runs [f] when the owner goes: what it holds of its own (a timer, a
  /// device), let go. What it defined through its participant goes by
  /// itself.
  void onDispose(void Function() f) => _Core.of(this).handles.keep(_Done(f));

  /// Writes its states from what it keeps elsewhere (a model, a device):
  /// [pull] runs when it is attached, whenever its participant's `sync` is
  /// called, and when [on] tells it something changed, once for all told
  /// in one turn; with the participant's other owners, as one tick. What
  /// it sets equal to what is kept changes nothing.
  void follow({required void Function() pull, Stream<void>? on}) {
    final c = _Core.of(this);
    c.follows.add(pull);
    if (on != null) c.syncOn(on);
    if (c.synced) c.participant!.batch(pull);
  }

  /// Listens to [stream] while it is attached: what its work reports on
  /// its own (a switch flipped by hand, a message come in), for it to
  /// write or say.
  void listen<T>({
    required Stream<T> stream,
    required void Function(T) onData,
  }) {
    final c = _Core.of(this);
    c.whenAttached(
      (_) => c.handles.keep(
        _Listening(
          stream.listen((x) {
            onData(x);
            c.moved();
          }),
        ),
      ),
    );
  }

  /// Hears [fact] while it is attached (another's, through its client:
  /// `hear(HouseClient.of(this).rang, ...)`): what [onData] writes, says
  /// and calls follows from the fact it hears, as a handler's follows from
  /// its call.
  void hear<T>({
    required IFactOf<T> fact,
    required void Function(T payload) onData,
  }) => listen(
    stream: fact.facts,
    onData: (f) => following(
      (by) => f.cause.child(f.message.id, by: by, word: f.message.fact),
      f.cause.by,
      () => onData(f.payload),
    ),
  );

  /// Who it answers where this runs: on whose behalf the call its handler
  /// serves came, or the fact it [hear]s; null where it answers nothing.
  Principal? get caller => answering;

  /// Runs [act] as the owner's own act, not an answer: what it writes,
  /// says and calls there, and in a timer it starts there, follows from
  /// nothing it was answering (a timer set in a handler, to act later on
  /// its own).
  R apart<R>(R Function() act) => serving_.apart(act);

  /// Runs [say], the fact it says there said under [id]: said again under
  /// the same id, it is dropped, and this answers false (in the host's
  /// process; across a connection the host drops it). For what comes from
  /// outside more than once: a platform's event, a webhook retried.
  bool once({required String id, required void Function() say}) =>
      serving_.once(id, say);

  /// Runs [writes] as one tick, as a handler's or a sync's are: seen
  /// whole, or not at all when it throws. Not attached, it just runs them.
  void together(void Function() writes) {
    final p = _Core.of(this).participant;
    p == null ? writes() : p.batch(writes);
  }

  /// Guards its command [word] (SPEC §10), named [id] in refusals and
  /// records: [check] answers why the call may not run, or null; asked
  /// before the handler, once it is attached. Who passes it is [check]'s to
  /// say: the rule is the owner's.
  void guard<P, R>({
    required String id,
    required ICommandWord<P, R> word,
    required String? Function(GuardCall<P> call) check,
  }) {
    final c = _Core.of(this);
    c.whenAttached(
      (p) => c.handles.keep(
        p.raw.addGuard(
          id,
          (call) => call.command.name == word.name
              ? check(
                  GuardCall._(
                    word.params.fromJson(call.params),
                    call.by,
                    word.name,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  /// Guards every command its participant serves, its own and those of
  /// the owners beside it (SPEC §10): [check] answers why a call of
  /// [command] on behalf of [by] may not run, or null. A rule of the whole
  /// participant, made by one owner: who may call what, beyond a word's
  /// callers. [id] names it in refusals and records.
  void guardAll({
    required String id,
    required String? Function(GuardCall<Map<String, Object?>> call) check,
  }) {
    final c = _Core.of(this);
    c.whenAttached(
      (p) => c.handles.keep(
        p.raw.whole.addGuard(
          id,
          (call) => check(GuardCall._(call.params, call.by, call.command.name)),
        ),
      ),
    );
  }

  /// The time now, by its registry's clock once it is attached (a test's
  /// clock, when it gives one).
  DateTime get now =>
      (_Core.of(this).participant?.raw.clock ?? clock_.clock).now();

  /// Tells whoever asks the registry (an agent, an editor, a plugin)
  /// the choices of [name] there are now (rooms: `HouseChoices.room`):
  /// [list] gives them, with their labels. What a `@ChoiceOf(name)` names
  /// is held to them. They are listed again on their own: when it is
  /// attached, after it followed its model, heard something or answered a
  /// call; what went goes of its keyed states keyed by [name] too.
  void choices({
    required String name,
    required Iterable<Choice> Function() list,
  }) {
    final c = _Core.of(this);
    final ch = _Choices(name, list);
    c.choices.add(ch);
    if (c.participant case final p? when c.group != null) ch.attach(p, c);
  }
}

/// An owner written by hand, for the package's own tests: it defines its
/// words in [define] and writes what it has now in [sync]. Not exported:
/// an app's owner extends the base its words' generator made.
abstract base class Owner implements IOwner, IHandle {
  /// Of [vocabulary], it speaks as the part of its name; without, as the
  /// participant.
  Owner({String? vocabulary}) {
    final c = _Core.of(this);
    IOwner.made(
      this,
      define: (p) {
        define(p.raw);
        if (changes case final s?) c.syncOn(s);
      },
      words: vocabulary == null ? null : WordSet.open(vocabulary),
    );
    c.follows.add(sync);
  }

  /// Told whenever what its states say may have changed: it is then
  /// synced, once for all told in one turn.
  Stream<void>? get changes => null;

  /// Defines its words through [p]; keep what each returns with `keep`.
  void define(IRawParticipant p) {}

  /// Writes its states as they are now. `IParticipant.sync` calls every
  /// owner's in one batch, so a change is seen whole.
  void sync() {}

  /// Keeps [h] to withdraw when the owner goes, and gives it back.
  H keep<H extends IHandle>(H h) => _Core.of(this).handles.keep(h);

  /// Withdraws its words, and leaves the participant it was attached to:
  /// its `sync` is not asked again. An owner that overrides it calls it.
  @override
  void dispose() => _Core.of(this).dispose();
}

/// A call a guard judges ([OwnerTools.guard], [OwnerTools.guardAll]):
/// what it asks, on whose behalf, of which command. What a guard is told
/// may grow; a guard written now keeps working.
final class GuardCall<P> {
  GuardCall._(this.params, this.by, this.command);

  /// Its params: typed, for a guard of one command; as JSON, for a guard
  /// of all.
  final P params;

  /// On whose behalf it comes.
  final Principal by;

  /// The command it calls.
  final String command;
}

/// One of what an owner gives to choose from ([OwnerTools.choices]): its
/// [id], what people see of it ([label], else the id), and what else a
/// chooser needs ([meta], JSON: the type of the value it takes...).
final class Choice {
  const Choice(this.id, {this.label, this.meta = const {}});

  final String id;
  final String? label;
  final Map<String, Object?> meta;
}

/// The choices of one kind an owner gives, as the registry was last told.
final class _Choices {
  _Choices(this.kind, this._list);

  final String kind;
  final Iterable<Choice> Function() _list;
  IParticipant? _participant;
  List<(String, String)> _known = const [];

  Iterable<EntityRef> _refs() => [
    for (final c in _list()) EntityRef(c.id, c.label, c.meta),
  ];

  void attach(IParticipant p, _Core core) {
    if (_participant != null) return;
    _participant = p;
    _known = _ids(_refs());
    core.handles.keep(p.raw.registerKind(EntityKind(kind, list: _refs)));
  }

  /// Each choice's id, and all it tells (its label, its meta).
  static List<(String, String)> _ids(Iterable<EntityRef> refs) => [
    for (final e in refs) (e.id, jsonEncode(e.toJson())),
  ];

  /// Compares the choices with the ones told last: when they differ, the
  /// registry is told. Answers the ids that went.
  Set<String> relist() {
    final p = _participant;
    if (p == null) return const {};
    final now = _ids(_refs());
    if (_same(now, _known)) return const {};
    final ids = {for (final (id, _) in now) id};
    final gone = {
      for (final (id, _) in _known)
        if (!ids.contains(id)) id,
    };
    _known = now;
    p.raw.entitiesChanged(kind);
    return gone;
  }

  static bool _same(List<(String, String)> a, List<(String, String)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The vocabulary [o]'s words are in, as its base said it; null for an
/// owner of no words.
WordSet? wordsOf(IOwner o) => _Core.of(o).words;

/// A handler of [part]'s answered: its owner lists its choices and asks
/// its checks again.
void ownerServed(IParticipant part) {
  for (final c in [...?_Core._ofPart[part]]) {
    c.moved();
  }
}

/// The owners attached to one participant (SPEC §22.3): each to the part
/// named by its vocabulary, synced as one tick, withdrawn with the
/// participant. A participant's own; code reaches it through the
/// owners a participant is made with (a guest's `attach`) and `sync`.
final class OwnerGroup {
  OwnerGroup(this.participant);

  final IParticipant participant;
  final Map<IOwner, _Core> _cores = {};
  final Set<_Core> _dirty = {};
  bool _disposed = false;

  /// The owners attached.
  Iterable<IOwner> get owners => _cores.keys;

  /// Attaches each of [owners] to the part named by its vocabulary
  /// (`participant.child('house')`), so its acts are told as its own; one
  /// of no words to the participant itself. In order; then writes what
  /// they have now, as one tick. All or none: when one cannot define its
  /// words, those attached here are withdrawn and the error goes on.
  void attach(Iterable<IOwner> owners) {
    if (_disposed) throw StateError('${participant.who} is gone');
    final list = [...owners];
    final cores = [for (final o in list) _Core.of(o)];
    final named = {
      for (final c in _cores.values)
        if (c.words case final w?) w.name: c.type,
    };
    for (final c in cores) {
      if (c.participant != null) throw StateError('${c.type} is attached');
      if (c.words case final w?) {
        if (named[w.name] case final other?) {
          throw StateError(
            '${participant.who} has an owner of ${w.name} already ($other): '
            'one vocabulary, one owner',
          );
        }
        named[w.name] = c.type;
      }
    }
    final attached = <IOwner>[];
    try {
      for (final (i, o) in list.indexed) {
        final c = cores[i];
        attached.add(o);
        c.attach(switch (c.words) {
          final w? => participant.child(w.name),
          null => participant,
        }, this);
        _cores[o] = c;
      }
    } catch (_) {
      for (final o in attached.reversed) {
        _end(o);
      }
      rethrow;
    }
    _sync(cores);
  }

  /// Writes what every owner has now, as one tick.
  void sync() => _sync([..._cores.values]);

  /// Syncs [owners] as one tick, each on its own: one that throws writes
  /// nothing, the others write what they have, and its error goes on
  /// after.
  void _sync(Iterable<_Core> owners) {
    Object? error;
    StackTrace? stack;
    participant.batch(() {
      for (final o in owners) {
        try {
          participant.batch(o.sync);
        } catch (e, s) {
          error ??= e;
          stack ??= s;
        }
      }
    });
    if (error case final e?) Error.throwWithStackTrace(e, stack!);
  }

  /// Withdraws [o]: by its own `dispose`, an [Owner] written by hand
  /// that may let go of more.
  static void _end(IOwner o) =>
      o is Owner ? o.dispose() : _Core.of(o).dispose();

  /// [c] was disposed on its own: it is synced no more.
  void _left(_Core c) {
    _cores.removeWhere((_, x) => identical(x, c));
    _dirty.remove(c);
  }

  /// How many groups' syncs are due and have not run, in this isolate:
  /// what a participant's `settle` waits for.
  static int _pending = 0;

  /// Completes once no owner's sync is due: those told of a change in the
  /// turns before have written.
  static Future<void> idle() async {
    do {
      await Future<void>.delayed(Duration.zero);
    } while (_pending > 0);
  }

  void _changed(_Core c) {
    final first = _dirty.isEmpty;
    _dirty.add(c);
    if (!first) return;
    _pending++;
    Timer.run(() {
      _pending--;
      final due = [
        for (final c in _cores.values)
          if (_dirty.contains(c)) c,
      ];
      _dirty.clear();
      if (_disposed) return;
      _sync(due);
    });
  }

  /// Withdraws the owners, the last attached first.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final o in [..._cores.keys].reversed) {
      _end(o);
    }
    _cores.clear();
  }
}

/// Ends the call being served as `failed` with [why]: for a handler whose
/// device or port said no. (A refusal with a code comes from the registry's
/// own stages, never from a handler.)
Never failCall(String why) => throw CallFailure(why);

/// Why a handler failed its call ([failCall]): told as it is, to people
/// too.
final class CallFailure implements Exception {
  const CallFailure(this.why);
  final String why;

  @override
  String toString() => why;
}

final class _Done implements IHandle {
  _Done(this._f);
  final void Function() _f;

  @override
  void dispose() => _f();
}

final class _Listening implements IHandle {
  _Listening(this._sub);
  final StreamSubscription<Object?> _sub;

  @override
  void dispose() => unawaited(_sub.cancel());
}
