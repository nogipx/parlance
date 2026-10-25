import 'dart:async';

import '../registry/cause.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/words.dart';
import '../remote/remote.dart';

/// What a screen reads and calls, whether the registry is in this process
/// or reached over remote: the values as they are now, read at once, told
/// when they change, and calls on behalf of one principal.
///
/// A screen asks for the states it draws ([changes]): over remote only
/// those come.
abstract interface class RegistryView {
  /// The value of [state] (of [key]) now; null when there is none, or the
  /// view does not have it.
  Object? read(String state, {String? key});

  /// Every value of [state], by key.
  Map<String?, Object?> readAll(String state);

  /// Told whenever any of [states] changes, and when the view loses or
  /// finds the registry again; while it is listened to, a remote view
  /// keeps those states.
  Stream<void> changes(Set<String> states);

  /// The facts of [fact] said from now on; while it is listened to, a
  /// remote view hears them.
  Stream<FactMessage> facts(String fact);

  /// The last [count] facts of [fact] the registry keeps, oldest first.
  Future<List<FactMessage>> recent(String fact, int count);

  /// Calls [command]; a read after it reads what it wrote.
  Future<CallResult<Object?>> call(String command, Map<String, Object?> params);

  /// Whether what it reads is the registry's now: false while a remote
  /// view is cut off from it.
  bool get synced;
}

/// A view through typed words (SPEC §18): the word fixes the types.
extension TypedView on RegistryView {
  ViewStateOf<T> state<T>(StateWord<T> word) => ViewStateOf._(this, word);
  ViewCommandOf<P, R> command<P, R>(CommandWord<P, R> word) =>
      ViewCommandOf._(this, word);
  ViewFactOf<T> fact<T>(FactWord<T> word) => ViewFactOf._(this, word);
}

/// A state as a view has it, typed.
final class ViewStateOf<T> {
  ViewStateOf._(this.view, this.word);

  final RegistryView view;
  final StateWord<T> word;

  /// Its value (of [key]) now.
  T? read({String? key}) => word.decode(view.read(word.name, key: key));

  /// Every value, by key.
  Map<String?, T> readAll() => {
    for (final e in view.readAll(word.name).entries)
      if (e.value != null) e.key: word.shape.fromJson(e.value),
  };
}

/// A command through a view, typed.
final class ViewCommandOf<P, R> {
  ViewCommandOf._(this.view, this.word);

  final RegistryView view;
  final CommandWord<P, R> word;

  /// Calls it; its answer decoded as the word says.
  Future<CallResult<R>> call(P params) async =>
      word.answer(await view.call(word.name, word.params.toJson(params)));
}

/// A fact through a view, typed.
final class ViewFactOf<T> {
  ViewFactOf._(this.view, this.word);

  final RegistryView view;
  final FactWord<T> word;

  /// The last [count] the registry keeps, oldest first.
  Future<List<Fact<T>>> recent(int count) async => [
    for (final m in await view.recent(word.name, count))
      Fact(word.shape.fromJson(m.payload), m),
  ];

  /// Those said from now on.
  Stream<Fact<T>> get stream =>
      view.facts(word.name).map((m) => Fact(word.shape.fromJson(m.payload), m));
}

/// A view of a registry in this process, calling as [by].
final class LocalView implements RegistryView {
  LocalView(this.registry, {required this.by});

  final Registry registry;

  /// On whose behalf it calls; it reads only what [by] may.
  final Principal by;

  @override
  Object? read(String state, {String? key}) =>
      registry.mayRead(by, state) ? registry.read(state, key: key) : null;

  @override
  Map<String?, Object?> readAll(String state) =>
      registry.mayRead(by, state) ? registry.readAll(state) : const {};

  @override
  Stream<void> changes(Set<String> states) => registry.ticks
      .where((t) => t.changes.any((c) => states.contains(c.state)))
      .map((_) {});

  @override
  Stream<FactMessage> facts(String fact) => registry.mayRead(by, fact)
      ? registry.facts(fact: fact)
      : const Stream.empty();

  @override
  Future<List<FactMessage>> recent(String fact, int count) async =>
      registry.mayRead(by, fact) ? registry.recent(fact, count) : const [];

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params,
  ) => registry.call(command, params, by: by);

  @override
  bool get synced => true;

  /// Views of one registry for one principal are the same view.
  @override
  bool operator ==(Object other) =>
      other is LocalView && other.registry == registry && other.by == by;

  @override
  int get hashCode => Object.hash(registry, by);
}

/// A view of a registry over remote: [mirror] follows its feed, [client]
/// calls. The mirror keeps the states and hears the facts the view's
/// listeners ask for, and no others.
final class MirrorView implements RegistryView {
  MirrorView(this.mirror, this.client);

  final RegistryMirror mirror;

  /// The session's client; after a lost connection, set the new one here
  /// and follow it with the mirror.
  SwitchboardClient client;

  final Map<String, int> _states = {};
  final Map<String, int> _facts = {};

  @override
  Object? read(String state, {String? key}) => mirror.read(state, key: key);

  @override
  Map<String?, Object?> readAll(String state) => mirror.readAll(state);

  @override
  Stream<void> changes(Set<String> states) {
    late StreamController<void> out;
    StreamSubscription<void>? sub;
    out = StreamController<void>(
      onListen: () {
        _want(_states, states, 1);
        // A tick of any state the mirror keeps, the values a subscription
        // brings, a lost or found connection: each told.
        sub = mirror.changes.listen((_) => out.add(null));
      },
      onCancel: () async {
        _want(_states, states, -1);
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<FactMessage> facts(String fact) {
    late StreamController<FactMessage> out;
    StreamSubscription<Tick>? sub;
    out = StreamController<FactMessage>(
      onListen: () {
        _want(_facts, {fact}, 1);
        sub = mirror.ticks.listen((t) {
          for (final f in t.facts) {
            if (f.fact == fact) out.add(f);
          }
        });
      },
      onCancel: () async {
        _want(_facts, {fact}, -1);
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<List<FactMessage>> recent(String fact, int count) =>
      client.recent(fact, count);

  /// Counts who asks for [names] in [wanted]; the mirror subscribes anew
  /// when what anyone asks for changes.
  void _want(Map<String, int> wanted, Set<String> names, int by) {
    var changed = false;
    for (final n in names) {
      final now = (wanted[n] ?? 0) + by;
      if (now <= 0) {
        changed |= wanted.remove(n) != null;
      } else {
        changed |= !wanted.containsKey(n);
        wanted[n] = now;
      }
    }
    if (!changed) return;
    unawaited(
      mirror
          .subscribe(states: {..._states.keys}, facts: {..._facts.keys})
          .catchError((Object _) {}),
    );
  }

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params,
  ) async {
    final r = await client.callAt(command, params);
    if ((r.epoch, r.seq) case (final epoch?, final seq?)) {
      await mirror.reach(epoch, seq);
    }
    return r.result;
  }

  @override
  bool get synced => mirror.synced;
}
