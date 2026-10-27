import 'dart:async';

import '../registry/cause.dart';
import '../registry/json.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/words.dart';

/// What a screen reads and calls, whether the registry is in this process
/// or reached over remote: the values as they are now, read at once, told
/// when they change, and calls on behalf of one principal.
///
/// A screen asks for the states it draws ([changes]): over remote only
/// those come.
abstract interface class IRegistryView {
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

  /// Whether the view's principal can use the word [word] now (SPEC §6.5):
  /// missing, not permitted, a command unavailable, or ready. Words come
  /// and go while the app runs, so a part asks this, or listens to
  /// [statusChanges], rather than checking once at start.
  WordStatus status(String word);

  /// [status] now, then whenever it changes.
  Stream<WordStatus> statusChanges(String word);
}

/// A view through typed words (SPEC §18): the word fixes the types.
extension TypedView on IRegistryView {
  ViewStateOf<T> state<T>(IStateWord<T> word) => ViewStateOf._(this, word);
  ViewCommandOf<P, R> command<P, R>(ICommandWord<P, R> word) =>
      ViewCommandOf._(this, word);
  ViewFactOf<T> fact<T>(IFactWord<T> word) => ViewFactOf._(this, word);
  ViewQueryOf<P, R> query<P, R>(IQueryWord<P, R> word) =>
      ViewQueryOf._(this, word);
}

/// A query through a view, typed.
final class ViewQueryOf<P, R> {
  ViewQueryOf._(this.view, this.word);

  final IRegistryView view;
  final IQueryWord<P, R> word;

  /// Asks it; asking again asks again.
  Future<CallResult<R>> ask(P params) async =>
      word.answer(await view.call(word.name, word.params.toJson(params)));

  WordStatus get status => view.status(word.name);
  Stream<WordStatus> get statusChanges => view.statusChanges(word.name);
}

/// A state as a view has it, typed.
final class ViewStateOf<T> {
  ViewStateOf._(this.view, this.word);

  final IRegistryView view;
  final IStateWord<T> word;

  /// Its value (of [key]) now.
  T? read({String? key}) => word.decode(view.read(word.name, key: key));

  /// Every value, by key.
  Map<String?, T> readAll() => {
    for (final e in view.readAll(word.name).entries)
      if (e.value != null) e.key: word.shape.fromJson(e.value),
  };

  /// Its value (of [key]) now, then whenever it changes; while listened
  /// to, a remote view keeps the state.
  Stream<T?> watch({String? key}) {
    late StreamController<T?> out;
    StreamSubscription<void>? sub;
    Object? last;
    var told = false;
    void tell() {
      final now = view.read(word.name, key: key);
      if (told && jsonEquals(now, last)) return;
      told = true;
      last = now;
      out.add(word.decode(now));
    }

    out = StreamController<T?>(
      onListen: () {
        sub = view.changes({word.name}).listen((_) => tell());
        tell();
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  WordStatus get status => view.status(word.name);
  Stream<WordStatus> get statusChanges => view.statusChanges(word.name);
}

/// A command through a view, typed.
final class ViewCommandOf<P, R> {
  ViewCommandOf._(this.view, this.word);

  final IRegistryView view;
  final ICommandWord<P, R> word;

  /// Calls it; its answer decoded as the word says.
  Future<CallResult<R>> call(P params) async =>
      word.answer(await view.call(word.name, word.params.toJson(params)));

  WordStatus get status => view.status(word.name);
  Stream<WordStatus> get statusChanges => view.statusChanges(word.name);
}

/// A fact through a view, typed.
final class ViewFactOf<T> {
  ViewFactOf._(this.view, this.word);

  final IRegistryView view;
  final IFactWord<T> word;

  /// The last [count] the registry keeps, oldest first.
  Future<List<Fact<T>>> recent(int count) async => [
    for (final m in await view.recent(word.name, count))
      Fact(word.shape.fromJson(m.payload), m),
  ];

  /// Those said from now on.
  Stream<Fact<T>> get stream =>
      view.facts(word.name).map((m) => Fact(word.shape.fromJson(m.payload), m));

  WordStatus get status => view.status(word.name);
  Stream<WordStatus> get statusChanges => view.statusChanges(word.name);
}

/// A view of a registry in this process, calling as [by].
final class LocalView implements IRegistryView {
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

  @override
  WordStatus status(String word) => registry.statusOf(word, by: by);

  @override
  Stream<WordStatus> statusChanges(String word) =>
      registry.statusChanges(word, by: by);

  /// Views of one registry for one principal are the same view.
  @override
  bool operator ==(Object other) =>
      other is LocalView && other.registry == registry && other.by == by;

  @override
  int get hashCode => Object.hash(registry, by);
}
