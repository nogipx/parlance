import 'dart:async';
import 'dart:convert';

import '../registry/cause.dart' show Principal;
import '../registry/descriptors.dart';
import '../registry/registry.dart';
import '../registry/words.dart' show Fact;
import 'serving.dart';
import 'serving.dart' as serving_ show apart;
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

/// An owner of words (SPEC §6, §19): code that defines its states,
/// commands and facts in [define], keeps their handles, and writes what it
/// has now in [sync]. `main` attaches it to a participant (SPEC §22.3:
/// `p.attach({'sound': Mixer(...)})`) and it speaks as the part of its
/// name; who that is, and what it may, `main` says when it makes the
/// participant, never the owner.
abstract base class Owner implements IHandle {
  final Handles _handles = Handles();
  IParticipant? _participant;
  OwnerGroup? _group;

  /// The participant it speaks through: the part `main` named it by.
  IParticipant get participant =>
      _participant ?? (throw StateError('$runtimeType is not attached'));

  /// Attached by [group] to [p], its part: defines its words; once.
  void _attach(IParticipant p, OwnerGroup group) {
    if (_participant != null) throw StateError('$runtimeType is attached');
    _participant = p;
    _group = group;
    (_made[this]?.define ?? define)(p);
    if (changes case final c?) listen(c, (_) => group._changed(this));
  }

  /// Told whenever what its states say may have changed (its model, a
  /// device): it is then synced, once for all told in one turn, and with
  /// the rest of its participant's owners as one tick. Without it,
  /// whoever changes the model calls `IParticipant.sync`.
  Stream<void>? get changes => null;

  /// Defines its words through [p]; keep what each returns with [keep].
  /// An owner base the generator made defines them itself ([made]), and
  /// one that extends it writes none of this.
  void define(IParticipant p) {}

  /// Writes its states as they are now, from what it keeps elsewhere (a
  /// model, a device). `IParticipant.sync` calls every owner's in one
  /// batch, so a change is seen whole. An owner the generator's base keeps
  /// the values of needs none: what it set is written for it.
  void sync() {}

  /// What a base the generator made does for [owner] that the owner does
  /// not write: [define] its words, and write before its [sync] what it
  /// set before it was attached. Called by the base, in its constructor.
  static void made(
    Owner owner, {
    required void Function(IParticipant p) define,
    void Function()? write,
  }) => _made[owner] = (define: define, write: write);

  static final Expando<
    ({void Function(IParticipant p) define, void Function()? write})
  >
  _made = Expando('made');

  void _sync() {
    _made[this]?.write?.call();
    sync();
  }

  /// Keeps [h] to withdraw when the owner goes, and gives it back.
  H keep<H extends IHandle>(H h) => _handles.keep(h);

  /// Listens to [stream] while it is attached: what its work reports on
  /// its own (a switch flipped by hand, a message come in), for it to write or
  /// emit.
  void listen<T>(Stream<T> stream, void Function(T) onData) =>
      keep(_Listening(stream.listen(onData)));

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

  /// Runs [writes] as one tick, as a handler's or `sync`'s are: seen
  /// whole, or not at all when it throws. Not attached, it just runs them.
  void together(void Function() writes) {
    final p = _participant;
    p == null ? writes() : p.batch(writes);
  }

  /// Registers a kind of entities it keeps, [list] the ones there are now.
  TrackedKind trackKind(String name, Iterable<EntityRef> Function() list) {
    final kind = TrackedKind._(participant, name, list);
    keep(participant.registerKind(EntityKind(name, list: list)));
    return kind;
  }

  /// Withdraws its words, and leaves the participant it was attached to:
  /// its `sync` is not asked again. An owner that overrides it calls it.
  @override
  void dispose() {
    _handles.dispose();
    _group?._left(this);
    _group = null;
  }
}

/// A kind of entities an owner keeps: it tells the registry when the
/// entities changed, and which ones went.
final class TrackedKind {
  TrackedKind._(this._participant, this.name, this._list)
    : _known = _ids(_list());

  final IParticipant _participant;
  final String name;
  final Iterable<EntityRef> Function() _list;
  List<(String, String)> _known;

  /// Each entity's id, and all it tells (its label, its meta).
  static List<(String, String)> _ids(Iterable<EntityRef> refs) => [
    for (final e in refs) (e.id, jsonEncode(e.toJson())),
  ];

  /// Compares the entities with the ones seen last: when they differ (an
  /// entity came, went, was renamed or tells otherwise), announces it. Answers the ids that
  /// went, for the owner to remove their keyed states.
  Set<String> sync() {
    final now = _ids(_list());
    if (_same(now, _known)) return const {};
    final ids = {for (final (id, _) in now) id};
    final gone = {
      for (final (id, _) in _known)
        if (!ids.contains(id)) id,
    };
    _known = now;
    _participant.entitiesChanged(name);
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
  final Map<String, Owner> _owners = {};
  final Set<Owner> _dirty = {};
  bool _disposed = false;

  /// The owners by the names of their parts.
  Map<String, Owner> get owners => Map.unmodifiable(_owners);

  /// Attaches each of [owners] to the part of its name
  /// (`participant.child(name)`), so its acts are told as its own, in
  /// order; then writes what they have now, as one tick. All or none: when
  /// one cannot define its words, those attached here are withdrawn and
  /// the error goes on.
  void attach(Map<String, Owner> owners) {
    if (_disposed) throw StateError('${participant.who} is gone');
    for (final name in owners.keys) {
      if (_owners.containsKey(name)) {
        throw StateError('${participant.who} has an owner named $name');
      }
    }
    for (final o in owners.values) {
      if (o._participant != null) {
        throw StateError('${o.runtimeType} is attached');
      }
    }
    final attached = <Owner>[];
    try {
      for (final MapEntry(key: name, value: o) in owners.entries) {
        attached.add(o);
        o._attach(participant.child(name), this);
        _owners[name] = o;
      }
    } catch (_) {
      for (final o in attached.reversed) {
        o.dispose();
      }
      rethrow;
    }
    _sync(owners.values);
  }

  /// Writes what every owner has now, as one tick.
  void sync() => _sync([..._owners.values]);

  /// Syncs [owners] as one tick, each on its own: one that throws writes
  /// nothing, the others write what they have, and its error goes on
  /// after.
  void _sync(Iterable<Owner> owners) {
    Object? error;
    StackTrace? stack;
    participant.batch(() {
      for (final o in owners) {
        try {
          participant.batch(o._sync);
        } catch (e, s) {
          error ??= e;
          stack ??= s;
        }
      }
    });
    if (error case final e?) Error.throwWithStackTrace(e, stack!);
  }

  /// [o] was disposed on its own: it is synced no more.
  void _left(Owner o) {
    _owners.removeWhere((_, x) => identical(x, o));
    _dirty.remove(o);
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

  void _changed(Owner o) {
    final first = _dirty.isEmpty;
    _dirty.add(o);
    if (!first) return;
    _pending++;
    Timer.run(() {
      _pending--;
      final due = [
        for (final o in _owners.values)
          if (_dirty.contains(o)) o,
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
    for (final o in [..._owners.values].reversed) {
      o.dispose();
    }
    _owners.clear();
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

final class _Listening implements IHandle {
  _Listening(this._sub);
  final StreamSubscription<Object?> _sub;

  @override
  void dispose() => unawaited(_sub.cancel());
}
