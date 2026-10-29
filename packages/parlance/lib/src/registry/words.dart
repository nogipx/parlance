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
/// §23). It is the only way a participant gets one: `main` grants
/// it (`participant(who, vocabularies:)`), so its name is written
/// once, where the words are. The generator makes one per `@Vocabulary`
/// class; one of hand-written enums is `WordSet('audio', [...])`.
final class WordSet {
  const WordSet(this.name, this.words, {this.from}) : open = false;

  /// A vocabulary whose words are not known before they come: a plugin's,
  /// a guest's in another language, a module's named at run time. Said
  /// so, never a vocabulary left out by mistake.
  const WordSet.open(this.name) : words = const [], open = true, from = null;

  final String name;
  final List<IWord> words;

  /// The package its words come from, and its version (`notes_words
  /// 1.2.0`), as the generator read them: what a client tells it was built
  /// against (SPEC §6.9).
  final String? from;

  /// Whether its words come at run time ([WordSet.open]).
  final bool open;

  /// Throws when a word lies outside [name].
  /// Throws when its name or a word's name is no name (SPEC §1), or a
  /// word is not named in it: told when the vocabulary is granted,
  /// at the start, for every word at once, not when one is defined.
  void check() {
    final bad = <String>[];
    if (!isValidName(name)) bad.add('the vocabulary name "$name"');
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

/// A state's name, its value's shape and, for a keyed one, the entity kind
/// of its keys. A host's enum of its states implements it.
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

/// The registry through typed words. The word fixes the types: a call is
/// made on what `command(word)` gives, so its params can only be the
/// word's.
extension TypedRegistry on Registry {
  StateOf<T> state<T>(IStateWord<T> word) => StateOf._(this, word);
  CommandOf<P, R> command<P, R>(ICommandWord<P, R> word) =>
      CommandOf._(this, word);
  QueryOf<P, R> query<P, R>(IQueryWord<P, R> word) => QueryOf._(this, word);
  FactOf<T> fact<T>(IFactWord<T> word) => FactOf._(this, word);
}

/// A state, typed.
final class StateOf<T> {
  StateOf._(this.registry, this.word);

  final Registry registry;
  final IStateWord<T> word;

  /// Defines it, with [by] its only writer.
  StateWriterOf<T> define({
    required Principal by,
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => StateWriterOf(
    registry.defineState(
      StateDescriptor(
        word.name,
        type: word.shape.type,
        key: word.key,
        readers: readers,
        meta: meta,
      ),
      by: by,
      shape: word.shape,
    ),
    word.shape,
  );

  /// Its value (of [key]); null when there is none.
  T? read({String? key}) => registry.readAs(word.name, word.shape, key: key);

  bool has({String? key}) => registry.has(word.name, key: key);

  /// Every value, by key; a null one too, of a state that may be null.
  Map<String?, T> readAll() => {
    for (final e in registry.readAll(word.name).entries)
      if (e.value != null || null is T) e.key: word.shape.fromJson(e.value),
  };

  /// Its value now, then on every change.
  Stream<T?> watch({String? key}) =>
      registry.watchAs(word.name, word.shape, key: key);

  /// Its value (of [key]) as the core reads a cell (SPEC §21.6): code
  /// that only reads takes a [IStateReader] and does not change when a cell
  /// becomes a state.
  IStateReader<T> reader({String? key}) => _StateReaderOf(this, key);
}

final class _StateReaderOf<T> implements IStateReader<T> {
  _StateReaderOf(this._state, this._key);
  final StateOf<T> _state;
  final String? _key;

  @override
  T? get value => _state.read(key: _key);

  @override
  bool get has => _state.has(key: _key);

  @override
  Stream<T?> watch() => _state.watch(key: _key);
}

/// The only write handle of a typed state.
///
/// It is a [IStateWriter] of an unkeyed state; [at] gives one of a key.
/// What a base the generator made writes a state through (SPEC §23.4):
/// part of the generator's contract, which a published words package's
/// `.g.dart` holds to, so it stays as it is; the participant's handles,
/// in this process and across a connection, are it.
abstract interface class IStateWriterOf<T> implements IHandle, IStateWriter<T> {
  /// Writes [value], of [key] for a keyed state.
  @override
  void set(T value, {String? key});

  /// Removes the value, of [key] for a keyed state.
  @override
  void remove({String? key});
}

/// What a base the generator made says a fact through (SPEC §23.4): the
/// generator's contract, as [IStateWriterOf] is.
abstract interface class IFactEmitterOf<T> implements IHandle, IFactEmitter<T> {
  /// Says [payload]; false when the registry dropped it as said before.
  @override
  bool emit(T payload);

  /// Says [payload] on behalf of [by], as far as the rights let it.
  bool emitFor(T payload, Principal by);
}

final class StateWriterOf<T>
    implements IHandle, IStateWriter<T>, IStateWriterOf<T> {
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

  /// The value of [key] as a [IStateWriter] (SPEC §21.6).
  IStateWriter<T> at(String key) => _KeyWriter(this, key);

  @override
  void dispose() => raw.dispose();
}

/// A keyed state as its owner keeps it (SPEC §23.4): what it set of each
/// key, read and written by key, as a map is. A base the generator made
/// holds one for each keyed state, and writes through it once attached.
final class Keyed<T> {
  final Map<String, T> _now = {};
  IStateWriterOf<T>? _writer;

  /// What it set of [key], if it did.
  T? operator [](String key) => _now[key];

  /// Sets the value of [key].
  void operator []=(String key, T value) {
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
    final kind = writer is StateWriterOf<T> ? writer.raw.descriptor.key : null;
    if (kind == null) return;
    (Zone.current[keyedDefined] as void Function(String, Keyed<Object?>)?)
        ?.call(kind, k);
  }

  /// For the base the generator made: writes what [k] was set before it
  /// was attached.
  static void writeAll<T>(Keyed<T> k) {
    for (final MapEntry(:key, :value) in k._now.entries) {
      k._writer!.set(value, key: key);
    }
  }
}

final class _KeyWriter<T> implements IStateWriter<T> {
  _KeyWriter(this._writer, this._key);
  final StateWriterOf<T> _writer;
  final String _key;

  @override
  void set(T value) => _writer.set(value, key: _key);

  @override
  void remove() => _writer.remove(key: _key);
}

/// What a call through an [ICommandCaller] of a command ended with when it was not
/// done: a refusal, a failure, no answer in time, or a lost answer.
final class CallNotDone implements Exception {
  const CallNotDone(this.result);

  final CallResult<Object?> result;

  @override
  String toString() => 'CallNotDone: ${result.whyNot}';
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

/// A command, typed.
final class CommandOf<P, R> {
  CommandOf._(this.registry, this.word);

  final Registry registry;
  final ICommandWord<P, R> word;

  /// Defines it with its [handler] (SPEC §6.2).
  IHandle define(
    FutureOr<R> Function(CommandCallOf<P> call) handler, {
    required Callers callers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    Availability? available,
  }) => registry.defineCommand(
    CommandDescriptor(
      word.name,
      params: word.params.type,
      returns: word.returns?.type,
      callers: callers,
      deadline: deadline,
      meta: meta,
    ),
    word.serve(handler),
    available: available,
    params: word.params,
    returns: word.returns,
  );

  /// Calls it with [params] on behalf of [by] (SPEC §9).
  Future<CallResult<R>> call(
    P params, {
    required Principal by,
    String? id,
    bool override = false,
    Cause? cause,
  }) async {
    final r = await registry.callKept(
      word.name,
      Kept(params, word.params),
      by: by,
      id: id,
      override: override,
      cause: cause,
    );
    return word.answer(r);
  }

  /// Why it cannot run now; null when it can.
  String? whyUnavailable() => registry.whyUnavailable(word.name);

  /// Calls on behalf of [by] as the core asks a port (SPEC §21.6): the
  /// answer of a done call, else [CallNotDone] with how it ended.
  ICommandCaller<P, R> caller({required Principal by}) =>
      _CommandCallerOf(this, by);
}

final class _CommandCallerOf<P, R> implements ICommandCaller<P, R> {
  _CommandCallerOf(this._command, this._by);
  final CommandOf<P, R> _command;
  final Principal _by;

  @override
  Future<R> call(P params) async {
    final r = await _command.call(params, by: _by);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }
}

/// A query, typed (SPEC §6.6): defined by its owner, asked by anyone its
/// askers let.
final class QueryOf<P, R> {
  QueryOf._(this.registry, this.word);

  final Registry registry;
  final IQueryWord<P, R> word;

  /// Defines it with its [handler]; [askers] who may ask, everyone when
  /// not said, as anyone may read a state that names no readers.
  IHandle define(
    FutureOr<R> Function(QueryAsk<P> ask) handler, {
    Callers? askers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    Availability? available,
  }) => registry.defineQuery(
    word.describeWith(
      askers: askers ?? const Callers({'*': Access.allow}),
      deadline: deadline,
      meta: meta,
    ),
    word.serve(handler),
    available: available,
    params: word.params,
    returns: word.returns,
  );

  /// Asks it with [params] on behalf of [by]; asking again asks again.
  Future<CallResult<R>> ask(
    P params, {
    required Principal by,
    Cause? cause,
  }) async => word.answer(
    await registry.callKept(
      word.name,
      Kept(params, word.params),
      by: by,
      cause: cause,
    ),
  );

  /// Why it cannot be asked now; null when it can.
  String? whyUnavailable() => registry.whyUnavailable(word.name);
}

/// A committed fact, its payload typed.
final class Fact<T> {
  const Fact(this.payload, this.message);

  final T payload;

  /// The fact as the registry has it: id, cause, time.
  final FactMessage message;

  Cause get cause => message.cause;
}

/// A fact, typed.
final class FactOf<T> {
  FactOf._(this.registry, this.word);

  final Registry registry;
  final IFactWord<T> word;

  /// Defines it, with [by] its producer.
  FactEmitterOf<T> define({
    required Principal by,
    bool open = false,
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => FactEmitterOf(
    registry.defineFact(
      FactDescriptor(
        word.name,
        type: word.shape.type,
        open: open,
        readers: readers,
        meta: meta,
      ),
      by: by,
      shape: word.shape,
    ),
    word.shape,
  );

  /// Another producer of an open fact.
  FactEmitterOf<T> producer({required Principal by}) => FactEmitterOf(
    registry.producer(word.name, by: by, shape: word.shape),
    word.shape,
  );

  Fact<T> _decode(FactMessage m) => Fact(word.shape.fromJson(m.payload), m);

  /// Its facts as they are committed.
  Stream<Fact<T>> get stream =>
      registry.factsAs(word.name, word.shape).map((f) => Fact(f.$1, f.$2));

  /// The last [n], oldest first.
  List<Fact<T>> recent([int? n]) => [
    for (final m in registry.recent(word.name, n)) _decode(m),
  ];

  /// Its payloads as the core hears a signal (SPEC §21.6).
  IFactListener<T> get listener => _FactListenerOf(this);
}

final class _FactListenerOf<T> implements IFactListener<T> {
  _FactListenerOf(this._fact);
  final FactOf<T> _fact;

  @override
  Stream<T> get stream => _fact.stream.map((f) => f.payload);
}

/// An emit handle of a typed fact; an [IFactEmitter] as the core's.
final class FactEmitterOf<T>
    implements IHandle, IFactEmitter<T>, IFactEmitterOf<T> {
  FactEmitterOf(this.raw, this._shape);

  /// The handle beneath: the registry's own, or a remote participant's.
  final IFactHandle raw;
  final Shape<T> _shape;

  /// As [RawFactEmitter.emit]; under the id of a `once` it runs in, when
  /// none is given.
  @override
  bool emit(T payload, {String? id, Cause? cause}) {
    final said = raw.emit(
      raw.shape == null ? _shape.toJson(payload) : payload,
      id: id ?? onceId,
      cause: cause,
    );
    if (!said) droppedOnce();
    return said;
  }

  /// Says it on behalf of [by], as far as the participant's rights let it
  /// speak for another: following from the call or the fact being
  /// answered where it is said, if one is.
  @override
  bool emitFor(T payload, Principal by, {String? id}) =>
      emit(payload, id: id, cause: inReplyAs(by) ?? Cause(by));

  @override
  void dispose() => raw.dispose();
}
