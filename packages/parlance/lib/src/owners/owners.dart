import 'dart:async';
import 'dart:convert';

import '../participant/participant.dart';
import '../registry/descriptors.dart';
import '../registry/registry.dart';

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
/// has now in [sync]. It speaks through the participant (SPEC §22) it is
/// attached to; who that is, and what it may, `main` says when it makes
/// the participant, never the owner.
abstract base class Owner implements IHandle {
  final Handles _handles = Handles();
  IParticipant? _participant;

  /// The participant it speaks through.
  IParticipant get participant =>
      _participant ?? (throw StateError('$runtimeType is not attached'));

  /// Attaches it to [p] and defines its words there; once.
  void attach(IParticipant p) {
    if (_participant != null) throw StateError('$runtimeType is attached');
    _participant = p;
    define(p);
  }

  /// Defines its words through [p]; keep what each returns with [keep].
  void define(IParticipant p);

  /// Writes its states as they are now. [Owners.sync] calls every owner's
  /// in one batch, so a change is seen whole.
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

/// Owners on one participant: a module of several, attached in order,
/// synced in one batch, withdrawn the last first. The participant is the
/// caller's: `main` made it, with the module's principal, namespaces and
/// rights, and it outlives the group.
final class Owners implements IHandle {
  Owners(this.participant, this.owners) {
    for (final o in owners) {
      o.attach(participant);
    }
    sync();
  }

  final IParticipant participant;
  final List<Owner> owners;

  /// Writes what every owner has now, as one tick.
  void sync() => participant.batch(() {
    for (final o in owners) {
      o.sync();
    }
  });

  @override
  void dispose() {
    for (final o in owners.reversed) {
      o.dispose();
    }
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
