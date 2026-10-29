import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart' as clock_;

import '../registry/cause.dart' show Principal;
import '../registry/descriptors.dart';
import '../registry/registry.dart';
import '../registry/words.dart' show Fact, ICommandWord;
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

/// An owner of words (SPEC §6, §19, §23.4): what `main` attaches to a
/// participant (`p.attach({'sound': Mixer(...)})`), to speak as the part
/// of its name; who that is, and what it may, `main` says when it makes
/// the participant, never the owner.
///
/// It has no members: what an owner does with the library it does by
/// [OwnerTools], extensions, so no name of an owner's own is the
/// library's, in this version or one to come. A base the generator made
/// implements it, and the owner extends that base.
abstract interface class IOwner {
  /// Called by an owner in its constructor (a base the generator made
  /// does it): [define] defines its words once it is attached, keeping
  /// each handle with [OwnerTools.keep]; [write], when given, writes what
  /// it set before it was attached, first of each sync.
  static void made(
    IOwner owner, {
    required void Function(IParticipant p) define,
    void Function()? write,
  }) {
    final c = _Core.of(owner);
    c.define = define;
    c.write = write;
  }
}

/// What the library keeps of an owner, beside it: an owner holds none of
/// it, so none of its names is the owner's.
final class _Core {
  _Core(this.type);

  static final Expando<_Core> _all = Expando('owner');
  static _Core of(IOwner o) => _all[o] ??= _Core(o.runtimeType);

  final Type type;
  final Handles handles = Handles();
  IParticipant? participant;
  OwnerGroup? group;
  void Function(IParticipant p)? define;
  void Function()? write;
  final List<void Function()> follows = [];

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
    participant = p;
    this.group = group;
    define?.call(p);
    final due = _due!;
    _due = null;
    for (final f in due) {
      f(p);
    }
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
    recheck();
  }

  bool _recheckDue = false;

  /// What its commands' checks read may have moved (its model, a device,
  /// what it heard): they are asked again, once in a turn, and a status
  /// told where it changed. No owner says so itself.
  void recheck() {
    if (_recheckDue || participant == null) return;
    _recheckDue = true;
    scheduleMicrotask(() {
      _recheckDue = false;
      if (group == null) return;
      participant?.raw.availabilityMayHaveChanged();
    });
  }

  void dispose() {
    handles.dispose();
    group?._left(this);
    group = null;
  }
}

/// What an owner does with the library (SPEC §19, §23.4): written in it as
/// its own, `listen(...)`, `caller`; a name the owner has of its own is
/// its own, and one these tools have is reached as `OwnerTools(this).x`.
extension OwnerTools on IOwner {
  /// The participant it speaks through: the part `main` named it by.
  /// Throws while it is not attached: what needs it waits in
  /// [whenAttached].
  IParticipant get participant =>
      _Core.of(this).participant ??
      (throw StateError('$runtimeType is not attached'));

  /// Keeps [h] to withdraw when the owner goes, and gives it back.
  H keep<H extends IHandle>(H h) => _Core.of(this).handles.keep(h);

  /// Runs [f] when the owner goes: what it holds of its own (a timer, a
  /// device), let go.
  void onDispose(void Function() f) => keep(_Done(f));

  /// Runs [f] with its participant once it is attached, after its words
  /// are defined; at once, when it is: what [OwnerTools] does not say
  /// (a guard, words named at run time).
  void whenAttached(void Function(IParticipant p) f) =>
      _Core.of(this).whenAttached(f);

  /// Writes its states from what it keeps elsewhere (a model, a device):
  /// [pull] runs when it is attached, whenever its participant's `sync` is
  /// called, and when [on] tells it something changed, once for all told
  /// in one turn; with the participant's other owners, as one tick. What
  /// it sets equal to what is kept changes nothing.
  void follow(void Function() pull, {Stream<void>? on}) {
    final c = _Core.of(this);
    c.follows.add(pull);
    if (on != null) c.syncOn(on);
    if (c.synced) c.participant!.batch(pull);
  }

  /// Listens to [stream] while it is attached: what its work reports on
  /// its own (a switch flipped by hand, a message come in), for it to
  /// write or say.
  void listen<T>(Stream<T> stream, void Function(T) onData) {
    final c = _Core.of(this);
    c.whenAttached(
      (_) => c.handles.keep(
        _Listening(
          stream.listen((x) {
            onData(x);
            c.recheck();
          }),
        ),
      ),
    );
  }

  /// Hears [facts] while it is attached (another's, through its client's
  /// `<fact>Facts`): what [onData] writes, says and calls follows from the
  /// fact it hears, as a handler's follows from its call.
  void hear<T>(Stream<Fact<T>> facts, void Function(T payload) onData) =>
      listen(
        facts,
        (f) => following(
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
  bool once(String id, void Function() say) => serving_.once(id, say);

  /// Runs [writes] as one tick, as a handler's or a sync's are: seen
  /// whole, or not at all when it throws. Not attached, it just runs them.
  void together(void Function() writes) {
    final p = _Core.of(this).participant;
    p == null ? writes() : p.batch(writes);
  }

  /// Guards its command [word] (SPEC §10): [check] answers why a call of
  /// [params] on behalf of [by] may not run, or null; asked before the
  /// handler, once it is attached. [id] names it in refusals and records.
  /// An overrider may pass it ([overridable]).
  void guard<P, R>(
    ICommandWord<P, R> word,
    String id,
    String? Function(P params, Principal by) check, {
    bool overridable = true,
  }) {
    final c = _Core.of(this);
    c.whenAttached(
      (p) => c.handles.keep(
        p.raw.addGuard(
          id,
          (call) => call.command.name == word.name
              ? check(word.params.fromJson(call.params), call.by)
              : null,
          overridable: overridable,
        ),
      ),
    );
  }

  /// The time now, by its registry's clock once it is attached (a test's
  /// clock, when it gives one).
  DateTime get now =>
      (_Core.of(this).participant?.raw.clock ?? clock_.clock).now();

  /// Registers a kind of entities it keeps, [list] the ones there are
  /// now; told to the registry once it is attached.
  TrackedKind trackKind(String name, Iterable<EntityRef> Function() list) {
    final kind = TrackedKind._(name, list);
    final c = _Core.of(this);
    c.whenAttached((p) {
      kind._attach(p);
      c.handles.keep(p.raw.registerKind(EntityKind(name, list: list)));
    });
    return kind;
  }
}

/// An owner written by hand, without a base the generator made (in tests
/// and tools): it defines its words in [define] and writes what it has
/// now in [sync]. Not in `schema.dart`: its members are its subclasses'
/// names, so it is no frozen contract.
abstract base class Owner implements IOwner, IHandle {
  Owner() {
    final c = _Core.of(this);
    IOwner.made(
      this,
      define: (p) {
        define(p.raw);
        if (changes case final s?) c.syncOn(s);
      },
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

  /// Withdraws its words, and leaves the participant it was attached to:
  /// its `sync` is not asked again. An owner that overrides it calls it.
  @override
  void dispose() => _Core.of(this).dispose();
}

/// A kind of entities an owner keeps: it tells the registry when the
/// entities changed, and which ones went.
final class TrackedKind {
  TrackedKind._(this.name, this._list);

  IParticipant? _participant;
  final String name;
  final Iterable<EntityRef> Function() _list;
  List<(String, String)> _known = const [];

  void _attach(IParticipant p) {
    _participant = p;
    _known = _ids(_list());
  }

  /// Each entity's id, and all it tells (its label, its meta).
  static List<(String, String)> _ids(Iterable<EntityRef> refs) => [
    for (final e in refs) (e.id, jsonEncode(e.toJson())),
  ];

  /// Compares the entities with the ones seen last: when they differ (an
  /// entity came, went, was renamed or tells otherwise), announces it.
  /// Answers the ids that went, for the owner to remove their keyed
  /// states.
  Set<String> sync() {
    final now = _ids(_list());
    if (_same(now, _known)) return const {};
    final ids = {for (final (id, _) in now) id};
    final gone = {
      for (final (id, _) in _known)
        if (!ids.contains(id)) id,
    };
    _known = now;
    _participant?.raw.entitiesChanged(name);
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

/// The owners attached to one participant (SPEC §22.3): each to the part
/// of its name, synced as one tick, withdrawn with the participant. A
/// participant's own; code reaches it through `IParticipant.attach` and
/// `sync`.
final class OwnerGroup {
  OwnerGroup(this.participant);

  final IParticipant participant;
  final Map<String, IOwner> _owners = {};
  final Map<IOwner, _Core> _cores = {};
  final Set<_Core> _dirty = {};
  bool _disposed = false;

  /// The owners by the names of their parts.
  Map<String, IOwner> get owners => Map.unmodifiable(_owners);

  /// Attaches each of [owners] to the part of its name
  /// (`participant.child(name)`), so its acts are told as its own, in
  /// order; then writes what they have now, as one tick. All or none: when
  /// one cannot define its words, those attached here are withdrawn and
  /// the error goes on.
  void attach(Map<String, IOwner> owners) {
    if (_disposed) throw StateError('${participant.who} is gone');
    for (final name in owners.keys) {
      if (_owners.containsKey(name)) {
        throw StateError('${participant.who} has an owner named $name');
      }
    }
    final cores = [for (final o in owners.values) _Core.of(o)];
    for (final c in cores) {
      if (c.participant != null) throw StateError('${c.type} is attached');
    }
    final attached = <IOwner>[];
    try {
      var i = 0;
      for (final MapEntry(key: name, value: o) in owners.entries) {
        final c = cores[i++];
        attached.add(o);
        c.attach(participant.child(name), this);
        _owners[name] = o;
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
    _cores.removeWhere((o, x) {
      if (!identical(x, c)) return false;
      _owners.removeWhere((_, y) => identical(y, o));
      return true;
    });
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
    _owners.clear();
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
