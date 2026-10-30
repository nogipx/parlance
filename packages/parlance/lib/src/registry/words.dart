import 'dart:async';

import '../participant/serving.dart'
    show droppedOnce, inReplyAs, keyedDefined, onceId;
import 'cause.dart';
import 'descriptors.dart';
import 'ids.dart';
import 'messages.dart';
import 'registry.dart';
import 'shapes.dart';

// Typed words (SPEC §18): a host names its states, commands and facts once,
// with their Dart types, and reads, writes and calls through them. The
// registry underneath keeps names and JSON, as remote participants and
// agents see it.

/// A word of any kind, by its name: what a vocabulary lists.
abstract interface class IWord {
  String get name;
}

/// A vocabulary: a module's words, all in its one [name] (SPEC §22.1,
/// §23). It is the only way a participant gets one: its owner brings it
/// (`participant(who, owners: [...])`), or `main` grants it for owners at
/// the other end or words named at run time (`vocabularies:`), so its
/// name is written once, where the words are. The generator makes one per
/// `@Vocabulary` class; one of hand-written enums is
/// `WordSet('house', [...])`.
final class WordSet {
  const WordSet(this.name, this.words, {this.from, this.dartName})
    : open = false;

  /// A vocabulary whose words are not known before they come: a plugin's,
  /// a guest's in another language, a module's named at run time. Said
  /// so, never a vocabulary left out by mistake.
  const WordSet.open(this.name)
    : words = const [],
      open = true,
      from = null,
      dartName = null;

  final String name;
  final List<IWord> words;

  /// The package its words come from, and its version (`notes_words
  /// 1.2.0`), as the generator read them: what a client tells it was built
  /// against (SPEC §6.9).
  final String? from;

  /// The name of the constant the generator made of it (`houseWords`),
  /// for what a message tells to give.
  final String? dartName;

  /// Whether its words come at run time ([WordSet.open]).
  final bool open;

  /// Throws when its name or a word's name is no name (SPEC §1), or a
  /// word is not named in it: told when the vocabulary is granted,
  /// at the start, for every word at once, not when one is defined.
  void check() {
    final bad = <String>[];
    if (!isValidVocabularyName(name)) {
      bad.add('the vocabulary name "$name" (one word, no .)');
    }
    for (final w in words) {
      try {
        checkWordName(w.name);
      } on ArgumentError catch (e) {
        bad.add('"${w.name}" (${e.message})');
        continue;
      }
      if (w.name != name && !w.name.startsWith('$name.')) {
        bad.add('"${w.name}" (not named in $name)');
      }
    }
    if (bad.isEmpty) return;
    throw ArgumentError(
      'the vocabulary $name has what is no word name: ${bad.join('; ')}. '
      'A name is lower-case words split by ., each from a letter, joined by _ '
      'or -',
    );
  }
}

/// A state's name, its value's shape and, for a keyed one, the choices
/// its keys are of. A host's enum of its states implements it.
abstract interface class IStateWord<T> implements IWord {
  @override
  String get name;
  Shape<T> get shape;
  String? get key;
}

/// A command's name, its params and what it answers ([returns] null: it
/// answers nothing, and [R] is `void`).
abstract interface class ICommandWord<P, R> implements IWord {
  @override
  String get name;
  RecordShape<P> get params;
  Shape<R>? get returns;
}

/// A query's name, its params and what it answers (SPEC §6.6, §18): a
/// question that changes nothing. Not a command: where a command is
/// called, a query is not passed, and where it is asked, it says so.
abstract interface class IQueryWord<P, R> implements IWord {
  @override
  String get name;
  RecordShape<P> get params;
  Shape<R> get returns;
}

/// A fact's name and its payload's shape.
abstract interface class IFactWord<T> implements IWord {
  @override
  String get name;
  Shape<T> get shape;
}

/// A state word named at run time (a device found, a plugin loaded), not
/// by a vocabulary class: `p.state(StateWordOf('sensor.$id', shape))`.
final class StateWordOf<T> implements IStateWord<T> {
  const StateWordOf(this.name, this.shape, {this.key});

  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// A fact word named at run time, as [StateWordOf] is.
final class FactWordOf<T> implements IFactWord<T> {
  const FactWordOf(this.name, this.shape);

  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// A state's value from its JSON, wherever it was read (a registry, a
/// mirror).
extension StateValues<T> on IStateWord<T> {
  T? decode(Object? json) => decodeKnown(shape, json);
}

/// A done call's value decoded by [shape] (`failed` when it does not
/// decode); any other end as it is.
CallResult<R> _answer<R>(
  String name,
  Shape<R>? shape,
  CallResult<Object?> raw,
) {
  if (raw is CallDone<Object?>) {
    // An answer the registry keeps by this shape is the value itself.
    if (keptAnswerOf(raw) case final kept? when identical(kept.shape, shape)) {
      return CallDone(kept.value as R);
    }
    try {
      return CallDone(shape == null ? null as R : shape.fromJson(raw.value));
    } on Object catch (e) {
      return CallFailed('the answer is not what $name says: $e');
    }
  }
  return raw as CallResult<R>;
}

/// A command's answer from what a call ended with, wherever it was called
/// (a registry, a client over remote).
extension CommandAnswers<P, R> on ICommandWord<P, R> {
  /// A done call's value decoded as the word says (`failed` when it does
  /// not decode); any other end as it is.
  CallResult<R> answer(CallResult<Object?> raw) => _answer(name, returns, raw);

  /// Its handler as the registry serves it: the params as the word has
  /// them, the answer as the command keeps it (SPEC §18); [servedBy] who
  /// serves it, for `inReply`.
  CommandHandler serve(
    FutureOr<R> Function(CommandCallOf<P> call) handler, {
    Principal? servedBy,
  }) => (c) {
    final asIs = answersAs(c, returns);
    Object? answer(R value) => asIs ? value : returns?.toJson(value);
    final out = handler(
      CommandCallOf(c, paramsAs(c, params), servedBy: servedBy),
    );
    return out is Future<R> ? out.then(answer) : answer(out);
  };
}

/// A query's answer, wherever it was asked.
extension QueryAnswers<P, R> on IQueryWord<P, R> {
  CallResult<R> answer(CallResult<Object?> raw) => _answer(name, returns, raw);

  /// Its descriptor, with [askers] who may ask (SPEC §6.6).
  QueryDescriptor describeWith({
    required Callers askers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
  }) => QueryDescriptor(
    name,
    params: params.type,
    returns: returns.type,
    askers: askers,
    deadline: deadline,
    meta: meta,
  );

  /// Its handler as the registry serves it: the params as the word has
  /// them, the answer as the query keeps it (SPEC §18).
  CommandHandler serve(FutureOr<R> Function(QueryAsk<P> ask) handler) => (c) {
    final asIs = answersAs(c, returns);
    Object? answer(R value) => asIs ? value : returns.toJson(value);
    final out = handler(QueryAsk(c, paramsAs(c, params)));
    return out is Future<R> ? out.then(answer) : answer(out);
  };
}

/// The only write handle of a typed state.
///
/// What a base the generator made writes a state through (SPEC §23.4):
/// part of the generator's contract, which a published words package's
/// `.g.dart` holds to, so it stays as it is; the participant's handles,
/// in this process and across a connection, are it.
abstract interface class IStateWriterOf<T> implements IHandle {
  /// Writes [value], of [key] for a keyed state.
  void set(T value, {String? key});

  /// Removes the value, of [key] for a keyed state.
  void remove({String? key});
}

/// What a base the generator made says a fact through (SPEC §23.4): the
/// generator's contract, as [IStateWriterOf] is.
abstract interface class IFactEmitterOf<T> implements IHandle {
  /// Says [payload], on behalf of [by] when given, as far as the rights
  /// let it; false when the registry dropped it as said before.
  bool say(T payload, {Principal? by});
}

final class StateWriterOf<T> implements IStateWriterOf<T> {
  StateWriterOf(this.raw, this._shape);

  /// The handle beneath: the registry's own, or a remote participant's.
  final IStateHandle raw;
  final Shape<T> _shape;

  /// As [RawStateWriter.set].
  /// The value as it is when the registry keeps it so (SPEC §18), else its
  /// JSON.
  @override
  void set(T value, {String? key, Cause? cause}) => raw.set(
    raw.shape == null ? _shape.toJson(value) : value,
    key: key,
    cause: cause,
  );

  @override
  void remove({String? key, Cause? cause}) =>
      raw.remove(key: key, cause: cause);

  @override
  void dispose() => raw.dispose();
}

/// A keyed state as its owner keeps it (SPEC §23.4): what it set of each
/// key, read by `of`, written by `set` and `remove`. A base the generator made
/// holds one for each keyed state, and writes through it once attached.
final class Keyed<T> {
  final Map<String, T> _now = {};
  IStateWriterOf<T>? _writer;

  /// What it set of [key], if it did.
  T? of(String key) => _now[key];

  /// Sets the value of [key].
  void set(String key, T value) {
    _now[key] = value;
    _writer?.set(value, key: key);
  }

  /// Removes the value of [key].
  void remove(String key) {
    _now.remove(key);
    _writer?.remove(key: key);
  }

  /// What it set, by key.
  Map<String, T> get all => Map.unmodifiable(_now);

  /// The keys it set.
  Iterable<String> get keys => _now.keys;

  /// For the base the generator made: [k] writes through [writer] from
  /// now on.
  static void attach<T>(Keyed<T> k, IStateWriterOf<T> writer) {
    k._writer = writer;
    final of = writer is StateWriterOf<T> ? writer.raw.descriptor.key : null;
    if (of == null) return;
    (Zone.current[keyedDefined] as void Function(String, Keyed<Object?>)?)
        ?.call(of, k);
  }

  /// For the base the generator made: writes what [k] was set before it
  /// was attached.
  static void writeAll<T>(Keyed<T> k) {
    for (final MapEntry(:key, :value) in k._now.entries) {
      k._writer!.set(value, key: key);
    }
  }
}

/// A state as a part that uses it reads it, through the client of its
/// words (SPEC §23.5): its value now, then whenever it changes. Read as
/// the owner reads its own ([Single.value]).
abstract interface class IStateOf<T> {
  /// Its value now; null while there is none.
  T? get value;

  /// [value], then whenever it changes.
  Stream<T?> get changes;
}

/// A keyed state as a part that uses it reads it (SPEC §23.5): read as the
/// owner reads its own ([Keyed.of], [Keyed.all]).
abstract interface class IKeyedOf<T> {
  /// The value of [key] now; null while there is none.
  T? of(String key);

  /// The value of every key there is, by key.
  Map<String, T> get all;

  /// The keys there are.
  Iterable<String> get keys;

  /// [of] [key], then whenever it changes.
  Stream<T?> changesOf(String key);

  /// [all], then whenever any key changes, comes or goes.
  Stream<Map<String, T>> get changes;
}

/// A fact as a part that hears it (SPEC §23.5): what is said from now on,
/// the payloads alone ([payloads]) or with their messages ([facts]), to
/// follow from (`hear`).
abstract interface class IFactOf<T> {
  /// What it says, as it is said from now on.
  Stream<T> get payloads;

  /// What it says and the message it came in: its id, its cause.
  Stream<Fact<T>> get facts;

  /// The last [count] said before now, the oldest first, as far as the
  /// host keeps them (`HostBounds.recentPerFact`): what a screen opened
  /// late shows first.
  Future<List<Fact<T>>> recent(int count);
}

/// A state as its owner keeps it (SPEC §23.4): what it set last, read by
/// [value], written by [set] and [remove]. A base the generator made
/// holds one for each state with no key, and writes through it once
/// attached; what was set before is written then.
final class Single<T> {
  T? _now;
  _Last _last = _Last.none;
  IStateWriterOf<T>? _writer;

  /// What it set last; null before it set anything, and after [remove].
  T? get value => _now;

  /// Sets the value.
  void set(T value) {
    _now = value;
    _last = _Last.set;
    _writer?.set(value);
  }

  /// Removes the value: the state is not there until set again.
  void remove() {
    _now = null;
    _last = _Last.removed;
    _writer?.remove();
  }

  /// For the base the generator made: [s] writes through [writer] from
  /// now on.
  static void attach<T>(Single<T> s, IStateWriterOf<T> writer) =>
      s._writer = writer;

  /// For the base the generator made: writes what [s] was set before it
  /// was attached.
  static void write<T>(Single<T> s) {
    switch (s._last) {
      case _Last.none:
        return;
      case _Last.set:
        s._writer!.set(s._now as T);
      case _Last.removed:
        s._writer!.remove();
    }
  }
}

enum _Last { none, set, removed }

/// What a call through a client ended with when it was not done: a refusal, a failure, no answer in time, or a lost answer.
final class CallNotDone implements Exception {
  const CallNotDone(this.result);

  final CallResult<Object?> result;

  @override
  String toString() => 'CallNotDone: ${result.why}';
}

/// A call being served, its params typed.
final class CommandCallOf<P> {
  CommandCallOf(this.raw, this.params, {this.servedBy});

  /// The call as the registry has it.
  final CommandCall raw;
  final P params;

  /// Who serves it: the participant (or its part) that defined the
  /// command; null for one defined on the registry itself.
  final Principal? servedBy;

  String get id => raw.id;

  /// The cause of the call: who called, and what led to it.
  Cause get cause => raw.cause;
  Principal get by => raw.by;
  Future<void> get expired => raw.expired;
  Cause causeFor(Principal by) => raw.causeFor(by);

  /// The call's span in the registry's log: its events and spans go with
  /// the call; `LogScope.noop`'s without a log.
  LogSpanHandle get span => raw.span;

  /// The cause of what its server writes, says and calls in reply:
  /// `causeFor(servedBy)`, so the trail shows the call led to it. Through
  /// a participant only; on the registry itself, `causeFor(owner)`.
  Cause get inReply => switch (servedBy) {
    final by? => raw.causeFor(by),
    null => throw StateError(
      '${raw.command} is served on the registry itself: use causeFor',
    ),
  };
}

/// A question being answered, its params typed: what a query's handler
/// gets. Unlike a command's call it offers no cause to write with: a
/// query writes nothing ([QueryEffect]). [askingFor] is the cause of a
/// question it asks in turn, so the trail and loop checks follow.
final class QueryAsk<P> {
  QueryAsk(this.raw, this.params);

  /// The call as the registry has it.
  final CommandCall raw;
  final P params;

  String get id => raw.id;

  /// Who asks, and why.
  Cause get cause => raw.cause;
  Principal get by => raw.by;
  Future<void> get expired => raw.expired;

  /// The cause of a query [by] asks in turn while answering this one.
  Cause askingFor(Principal by) => raw.causeFor(by);

  /// The question's span in the registry's log; `LogScope.noop`'s without
  /// a log.
  LogSpanHandle get span => raw.span;
}

/// A committed fact, its payload typed.
final class Fact<T> {
  const Fact._(this.payload, this._message);

  final T payload;
  final FactMessage _message;

  /// Its id: said again under it, it is dropped.
  String get id => _message.id;

  /// On whose behalf it was said.
  Principal get by => _message.cause.by;

  /// When it was said.
  DateTime get at => _message.at;
}

/// [payload], said in [message]: the library's.
Fact<T> factIn<T>(T payload, FactMessage message) => Fact._(payload, message);

/// A fact as the library and its tools have it: the message it came in,
/// its cause.
extension RawFact<T> on Fact<T> {
  FactMessage get message => _message;
  Cause get cause => _message.cause;
}

/// An emit handle of a typed fact.
final class FactEmitterOf<T> implements IFactEmitterOf<T> {
  FactEmitterOf(this.raw, this._shape);

  /// The handle beneath: the registry's own, or a remote participant's.
  final IFactHandle raw;
  final Shape<T> _shape;

  /// Says [payload], on behalf of [by] when given, as far as the
  /// participant's rights let it speak for another: following from the
  /// call or the fact being answered where it is said, if one is.
  @override
  bool say(T payload, {Principal? by, String? id}) => emit(
    payload,
    id: id,
    cause: by == null ? null : inReplyAs(by) ?? Cause(by),
  );

  /// As [RawFactEmitter.emit], with a cause of the caller's own: the
  /// library's and its tools'. Under the id of a `once` it runs in, when
  /// none is given.
  bool emit(T payload, {String? id, Cause? cause}) {
    final said = raw.emit(
      raw.shape == null ? _shape.toJson(payload) : payload,
      id: id ?? onceId,
      cause: cause,
    );
    if (!said) droppedOnce();
    return said;
  }

  @override
  void dispose() => raw.dispose();
}
