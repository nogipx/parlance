import '../registry/address.dart';
import '../registry/access.dart';
// Internal to the library: what these files show is not a promise
// Documented surface lives in schema.dart and app.dart.
// ignore_for_file: public_member_api_docs
import 'dart:async';

import '../registry/cause.dart';
import '../registry/compat.dart';
import '../registry/descriptors.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/shapes.dart';
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

  /// [read] as [shape] has it (SPEC §18): the value itself when the
  /// registry is in this process and keeps it by [shape], else its JSON
  /// decoded.
  T? readAs<T>(String state, Shape<T> shape, {String? key});

  /// Every value of [state], by key.
  Map<String?, Object?> readAll(String state);

  /// [readAll] as [shape] has it, each value as [readAs] reads it: one it
  /// cannot read is left out, as [readAs] answers null for it.
  Map<String?, T> readAllAs<T>(String state, Shape<T> shape);

  /// Every value of [state] now, by key, also of a state the view does not
  /// keep (SPEC §20): what a part that names words at run time reads (a
  /// plugin, an agent). Across a connection the view waits until it has
  /// it, and with [keep] keeps it from then on, so a read after answers at
  /// once; without, it lets it go again (a look at many states at once).
  /// One it may not read is empty.
  Future<Map<String?, Object?>> fetch(String state, {bool keep = true});

  /// Told whenever any of [states] changes, and when the view loses or
  /// finds the registry again; while it is listened to, a remote view
  /// keeps those states.
  Stream<void> changes(Set<String> states);

  /// The facts of [fact] said from now on; while it is listened to, a
  /// remote view hears them, from once the host heard it listen (a
  /// remote participant's `settle` waits for that). Across a connection
  /// those said while it was away past what the host retains are gone,
  /// as its participant's `errors` tells (`factsLost`).
  Stream<FactMessage> facts(String fact);

  /// [facts] with their payloads as [shape] has them (SPEC §18).
  Stream<(T, FactMessage)> factsAs<T>(String fact, Shape<T> shape);

  /// The last [count] facts of [fact] the registry keeps, oldest first.
  Future<List<FactMessage>> recent(String fact, int count);

  /// Calls [command]; a read after it reads what it wrote.
  Future<CallResult<Object?>> call(String command, Map<String, Object?> params);

  /// [call] with [params] as [shape] has them (SPEC §18): a command in
  /// this process that keeps its params by [shape] takes them as they are,
  /// and its answer comes as it keeps it; else they go as JSON.
  Future<CallResult<Object?>> callAs(
    String command,
    Object? params,
    Shape<Object?> shape,
  );

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

  /// The word [word] as the view sees it defined now: what a typed status
  /// holds the word code was built against to (SPEC §6.5); null when it
  /// sees none.
  Descriptor? descriptor(String word);

  /// Tells the registry the view's code was built against [words] (SPEC
  /// §6.9), for it to say where one is defined otherwise
  /// (`Registry.mismatches`), now and whenever words come and go; across
  /// a connection the host is told, and told again on a new session. A
  /// generated client tells it as it is made, with [from], the words
  /// package and its version (`notes_words 1.2.0`), for a mismatch to say
  /// which. Diagnostics only: nothing waits on it, nothing is refused by
  /// it.
  void builtAgainst(Iterable<IWord> words, {String? from, Principal? target});
}

/// Whether [word] is there for [view] now, as the code holding [word] was
/// built against it (SPEC §6.5): its status by name, and a word there
/// whose kind or types break a promise of [word] (§23.3) is
/// [WordMismatch], saying where.
WordStatus wordStatus(IRegistryView view, IWord word, {Principal? target}) {
  final name = target == null
      ? word.name
      : WordAddress(target, word.name).toString();
  final now = view.status(name);
  if (now is WordMissing || now is WordNotPermitted) return now;
  final live = view.descriptor(name);
  if (live == null) return now;
  final breaks = wordBreaks(word, live);
  return breaks.isEmpty ? now : WordMismatch(breaks);
}

/// [wordStatus] now, then whenever it changes.
Stream<WordStatus> wordStatusChanges(
  IRegistryView view,
  IWord word, {
  Principal? target,
}) => view
    .statusChanges(
      target == null ? word.name : WordAddress(target, word.name).toString(),
    )
    .map((_) => wordStatus(view, word, target: target))
    .distinct();

/// Each of [words] there for [view] but not as the code was built against,
/// by name, with where it breaks; empty when every one keeps its promises.
/// For a part to check as it starts, in development:
/// `assert(wordMismatches(p, ordersWords.words).isEmpty)`.
Map<String, List<WordBreak>> wordMismatches(
  IRegistryView view,
  Iterable<IWord> words, {
  Principal? target,
}) => {
  for (final w in words)
    if (wordStatus(view, w, target: target) case WordMismatch(:final breaks))
      (target == null ? w.name : WordAddress(target, w.name).toString()):
          breaks,
};

/// A view of a registry in this process, calling as [by].
final class LocalView implements IRegistryView {
  LocalView(this.registry, {required this.by, this.cause});

  final Registry registry;

  /// On whose behalf it calls; it reads only what [by] may.
  final Principal by;

  /// Optional verified attribution for reads made through a participant.
  final Cause? Function()? cause;

  @override
  Object? read(String state, {String? key}) =>
      registry.checkRead(by, state, cause: cause?.call())
      ? registry.read(state, key: key)
      : null;

  @override
  T? readAs<T>(String state, Shape<T> shape, {String? key}) =>
      registry.checkRead(by, state, cause: cause?.call())
      ? registry.readAs(state, shape, key: key)
      : null;

  @override
  Map<String?, Object?> readAll(String state) =>
      registry.checkRead(by, state, cause: cause?.call())
      ? registry.readAll(state)
      : const {};

  @override
  Map<String?, T> readAllAs<T>(String state, Shape<T> shape) =>
      registry.checkRead(by, state, cause: cause?.call())
      ? registry.readAllAs(state, shape)
      : const {};

  /// A read by name, as a part outside the build makes it: counted as
  /// [by]'s use of the word (SPEC §6.8).
  @override
  Future<Map<String?, Object?>> fetch(String state, {bool keep = true}) async {
    if (!registry.checkRead(by, state, cause: cause?.call())) return const {};
    registry.usedBy(state, by);
    return registry.readAll(state);
  }

  /// An old name of a word (SPEC §6.4) is told the word's changes.
  @override
  Stream<void> changes(Set<String> states) => Stream.multi((out) {
    var closed = false;
    void tell() {
      if (!closed) out.add(null);
    }

    void end() {
      if (!closed) {
        closed = true;
        out.close();
      }
    }

    for (final state in states) {
      registry.checkRead(
        by,
        state,
        operation: AccessOperation.subscribe,
        cause: cause?.call(),
      );
    }
    bool wanted(String word) =>
        states.any((s) => registry.canonical(s) == word);
    final ticks = registry.ticks.listen(
      (t) {
        if (t.changes.any(
          (c) => wanted(c.state) && registry.mayRead(by, c.state),
        )) {
          tell();
        }
      },
      onError: out.addError,
      onDone: end,
    );
    final access = registry.accessChanges.listen((word) {
      if (wanted(word)) tell();
    });
    final catalog = registry.catalogChanges.listen((event) {
      final word = switch (event) {
        DescriptorAdded(:final descriptor) => descriptor.name,
        DescriptorRemoved(:final descriptor) => descriptor.name,
        AliasChanged(:final alias) => alias,
        AccessChanged() => null,
      };
      if (word != null && wanted(registry.canonical(word))) tell();
    });
    out.onPause = () {
      ticks.pause();
      access.pause();
      catalog.pause();
    };
    out.onResume = () {
      ticks.resume();
      access.resume();
      catalog.resume();
    };
    out.onCancel = () async {
      closed = true;
      await ticks.cancel();
      await access.cancel();
      await catalog.cancel();
    };
  });

  Stream<T> _hearing<T>(String fact, Stream<T> events, int Function(T) seq) {
    var allowed = registry.mayRead(by, fact);
    var after = allowed ? -1 : registry.seq;
    return Stream<T>.multi((out) {
      allowed = registry.mayRead(by, fact);
      after = allowed ? -1 : registry.seq;
      registry.checkRead(
        by,
        fact,
        operation: AccessOperation.subscribe,
        cause: cause?.call(),
      );
      final policy = registry.accessChanges.listen((word) {
        if (registry.canonical(fact) != word) return;
        final now = registry.mayRead(by, fact);
        if (!now || !allowed) after = registry.seq;
        allowed = now;
      });
      final sub = events.listen(
        out.add,
        onError: out.addError,
        onDone: out.close,
      );
      out.onPause = sub.pause;
      out.onResume = sub.resume;
      out.onCancel = () async {
        await sub.cancel();
        await policy.cancel();
      };
    }).where((event) => registry.mayRead(by, fact) && seq(event) > after);
  }

  @override
  Stream<FactMessage> facts(String fact) =>
      _hearing(fact, registry.facts(fact: fact), (f) => f.seq);

  @override
  Stream<(T, FactMessage)> factsAs<T>(String fact, Shape<T> shape) =>
      _hearing(fact, registry.factsAs(fact, shape), (f) => f.$2.seq);

  @override
  Future<List<FactMessage>> recent(String fact, int count) async =>
      registry.checkRead(by, fact, cause: cause?.call())
      ? registry.recent(fact, count)
      : const [];

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params,
  ) => registry.call(command, params, by: by);

  @override
  Future<CallResult<Object?>> callAs(
    String command,
    Object? params,
    Shape<Object?> shape,
  ) => registry.callKept(command, Kept(params, shape), by: by);

  @override
  bool get synced => true;

  @override
  WordStatus status(String word) => registry.statusOf(word, by: by);

  @override
  Stream<WordStatus> statusChanges(String word) =>
      registry.statusChanges(word, by: by);

  @override
  Descriptor? descriptor(String word) => registry.descriptorOf(word);

  /// Held while the registry lives: a view has no end of its own.
  @override
  void builtAgainst(Iterable<IWord> words, {String? from, Principal? target}) =>
      registry.builtAgainst(by, {
        for (final w in words)
          (target == null ? w.name : WordAddress(target, w.name).toString()):
              schemaOfWord(w),
      }, from: from);

  /// Views of one registry for one principal are the same view.
  @override
  bool operator ==(Object other) =>
      other is LocalView && other.registry == registry && other.by == by;

  @override
  int get hashCode => Object.hash(registry, by);
}
