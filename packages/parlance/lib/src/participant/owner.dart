import 'dart:async';
import 'dart:convert';

import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/words.dart';
import 'participant.dart';

/// Handles to withdraw together: what an owner put in a registry.
final class Handles implements IHandle {
  final List<IHandle> _all = [];
  bool _disposed = false;

  /// Keeps [h] to withdraw with the rest, and gives it back as it is:
  /// `_mode = handles.keep(r.state(Mode.word).define(by: me));`
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

  /// The participant it speaks through: the part `main` named it by.
  IParticipant get participant =>
      _participant ?? (throw StateError('$runtimeType is not attached'));

  /// Attached by [group] to [p], its part: says there what it owns and
  /// uses, and defines its words; once. A word of [words] outside the
  /// participant's namespaces is refused before anything is defined.
  void _attach(IParticipant p, OwnerGroup group) {
    if (_participant != null) throw StateError('$runtimeType is attached');
    final d = Declaration(
      owns: {for (final w in words) w.name},
      uses: {for (final u in uses) u.word.name: u.required},
    );
    if (!d.isEmpty) keep(p.declare(d));
    _participant = p;
    define(p);
    if (changes case final c?) listen(c, (_) => group._changed(this));
  }

  /// Told whenever what its states say may have changed (its model, a
  /// device): it is then synced, once for all told in one turn, and with
  /// the rest of its participant's owners as one tick. Without it,
  /// whoever changes the model calls `IParticipant.sync`.
  Stream<void>? get changes => null;

  /// The words it owns (SPEC §6.7): `[...OrdersState.values, ...]`, told
  /// in `describe` with what it [uses]. It may define others too, within
  /// its namespaces (a name known only at run time); a word listed here
  /// outside them is refused when it attaches.
  Iterable<IWord> get words => const [];

  /// Defines its words through [p]; keep what each returns with [keep].
  void define(IParticipant p);

  /// The words of others it uses (SPEC §19.1): those [Use.required] it
  /// cannot work without, checked by `IParticipant.checkUses` once the
  /// app's owners are attached; the rest it handles while they are
  /// missing.
  Iterable<Use> get uses => const [];

  /// Writes its states as they are now. `IParticipant.sync` calls every
  /// owner's in one batch, so a change is seen whole.
  void sync() {}

  /// Keeps [h] to withdraw when the owner goes, and gives it back.
  H keep<H extends IHandle>(H h) => _handles.keep(h);

  /// Listens to [stream] while it is attached: what its work reports on
  /// its own (a switch flipped by hand, a message come in), for it to write or
  /// emit.
  void listen<T>(Stream<T> stream, void Function(T) onData) =>
      keep(_Listening(stream.listen(onData)));

  /// Registers a kind of entities it keeps, [list] the ones there are now.
  TrackedKind trackKind(String name, Iterable<EntityRef> Function() list) {
    final kind = TrackedKind._(participant, name, list);
    keep(participant.registerKind(EntityKind(name, list: list)));
    return kind;
  }

  /// Withdraws its words.
  @override
  void dispose() => _handles.dispose();
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
/// participant's own; code reaches it through `IParticipant.attach`,
/// `sync` and `checkUses`.
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
  /// order; then writes what they have now, as one tick.
  void attach(Map<String, Owner> owners) {
    if (_disposed) throw StateError('${participant.who} is gone');
    for (final name in owners.keys) {
      if (_owners.containsKey(name)) {
        throw StateError('${participant.who} has an owner named $name');
      }
    }
    for (final MapEntry(key: name, value: o) in owners.entries) {
      o._attach(participant.child(name), this);
      _owners[name] = o;
    }
    participant.batch(() {
      for (final o in owners.values) {
        o.sync();
      }
    });
  }

  /// Writes what every owner has now, as one tick.
  void sync() => participant.batch(() {
    for (final o in _owners.values) {
      o.sync();
    }
  });

  void _changed(Owner o) {
    final first = _dirty.isEmpty;
    _dirty.add(o);
    if (!first) return;
    Timer.run(() {
      final due = [
        for (final o in _owners.values)
          if (_dirty.contains(o)) o,
      ];
      _dirty.clear();
      if (_disposed) return;
      participant.batch(() {
        for (final o in due) {
          o.sync();
        }
      });
    });
  }

  /// Whether every owner has the words it says it needs (SPEC §19.1): each
  /// [Use.required] there for its part, not missing and not withheld from
  /// it; a command that cannot run now is there. Call it once every
  /// participant of the app has its owners, as words of one may be
  /// another's; it throws [UnmetUses] naming all that is not met, so
  /// `main` stops with a clear message rather than a part failing later.
  Future<void> checkUses() async {
    await participant.settle();
    final unmet = <UnmetUse>[];
    for (final o in _owners.values) {
      for (final u in o.uses) {
        if (!u.required) continue;
        final status = o.participant.status(u.word.name);
        if (status is WordMissing || status is WordNotPermitted) {
          unmet.add(UnmetUse(o.participant.who, u.word.name, status));
        }
      }
    }
    if (unmet.isNotEmpty) throw UnmetUses(unmet);
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

/// A word an owner uses ([Owner.uses]).
final class Use {
  /// One it cannot work without: `IParticipant.checkUses` fails while it is not
  /// there.
  const Use.required(this.word) : required = true;

  /// One it handles being missing, not permitted or unavailable.
  const Use.optional(this.word) : required = false;

  final IWord word;
  final bool required;
}

/// A required word an owner does not have: the part that needs it, the
/// word, and what its status says.
final class UnmetUse {
  const UnmetUse(this.by, this.word, this.status);
  final Principal by;
  final String word;
  final WordStatus status;

  @override
  String toString() => switch (status) {
    WordNotPermitted() => '$by needs $word: not permitted',
    _ => '$by needs $word: missing',
  };
}

/// The words owners need and do not have, all of them.
final class UnmetUses extends StateError {
  UnmetUses(this.unmet) : super(unmet.join('; '));
  final List<UnmetUse> unmet;
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
