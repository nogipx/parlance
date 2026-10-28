import 'dart:async';

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
  const WordSet(this.name, this.words) : open = false;

  /// A vocabulary whose words are not known before they come: a plugin's,
  /// a guest's in another language, a module's named at run time. Said
  /// so, never a vocabulary left out by mistake.
  const WordSet.open(this.name) : words = const [], open = true;

  final String name;
  final List<IWord> words;

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

final Expando<(Shape<Object?>, Object?)> _decoded = Expando('decoded');

/// A state's value from its JSON, wherever it was read (a registry, a
/// mirror).
extension StateValues<T> on IStateWord<T> {
  T? decode(Object? json) {
    if (json == null) return null;
    // A registry's values are frozen, so one decoded value serves every
    // read of the same JSON; a write puts another JSON there.
    if (json is! List && json is! Map) return shape.fromJson(json);
    final cached = _decoded[json];
    if (cached != null && identical(cached.$1, shape)) return cached.$2 as T;
    final value = shape.fromJson(json);
    _decoded[json] = (shape, value);
    return value;
  }
}

/// A done call's value decoded by [shape] (`failed` when it does not
/// decode); any other end as it is.
CallResult<R> _answer<R>(
  String name,
  Shape<R>? shape,
  CallResult<Object?> raw,
) {
  if (raw case CallDone(:final value)) {
    try {
      return CallDone(shape == null ? null as R : shape.fromJson(value));
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

  /// Its handler as the registry serves it: params decoded, the answer
  /// encoded.
  CommandHandler serve(FutureOr<R> Function(QueryAsk<P> ask) handler) => (c) {
    final out = handler(QueryAsk(c, params.fromJson(c.params)));
    return out is Future<R> ? out.then(returns.toJson) : returns.toJson(out);
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
    ),
    word.shape,
  );

  T? _decode(Object? json) => word.decode(json);

  /// Its value (of [key]); null when there is none.
  T? read({String? key}) => _decode(registry.read(word.name, key: key));

  bool has({String? key}) => registry.has(word.name, key: key);

  /// Every value, by key; a null one too, of a state that may be null.
  Map<String?, T> readAll() => {
    for (final e in registry.readAll(word.name).entries)
      if (e.value != null || null is T) e.key: word.shape.fromJson(e.value),
  };

  /// Its value now, then on every change.
  Stream<T?> watch({String? key}) =>
      registry.watch(word.name, key: key).map(_decode);

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
final class StateWriterOf<T> implements IHandle, IStateWriter<T> {
  StateWriterOf(this.raw, this._shape);

  /// The handle beneath: the registry's own, or a remote participant's.
  final IStateHandle raw;
  final Shape<T> _shape;

  /// As [RawStateWriter.set].
  @override
  void set(T value, {String? key, Cause? cause}) =>
      raw.set(_shape.toJson(value), key: key, cause: cause);

  @override
  void remove({String? key, Cause? cause}) =>
      raw.remove(key: key, cause: cause);

  /// The value of [key] as a [IStateWriter] (SPEC §21.6).
  IStateWriter<T> at(String key) => _KeyWriter(this, key);

  @override
  void dispose() => raw.dispose();
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
  }) {
    Object? answer(R value) => word.returns?.toJson(value);
    return registry.defineCommand(
      CommandDescriptor(
        word.name,
        params: word.params.type,
        returns: word.returns?.type,
        callers: callers,
        deadline: deadline,
        meta: meta,
      ),
      (c) {
        final out = handler(CommandCallOf(c, word.params.fromJson(c.params)));
        return out is Future<R> ? out.then(answer) : answer(out);
      },
      available: available,
    );
  }

  /// Calls it with [params] on behalf of [by] (SPEC §9).
  Future<CallResult<R>> call(
    P params, {
    required Principal by,
    String? id,
    bool override = false,
    Cause? cause,
  }) async {
    final r = await registry.call(
      word.name,
      word.params.toJson(params),
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
  );

  /// Asks it with [params] on behalf of [by]; asking again asks again.
  Future<CallResult<R>> ask(
    P params, {
    required Principal by,
    Cause? cause,
  }) async => word.answer(
    await registry.call(
      word.name,
      word.params.toJson(params),
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
    ),
    word.shape,
  );

  /// Another producer of an open fact.
  FactEmitterOf<T> producer({required Principal by}) =>
      FactEmitterOf(registry.producer(word.name, by: by), word.shape);

  Fact<T> _decode(FactMessage m) => Fact(word.shape.fromJson(m.payload), m);

  /// Its facts as they are committed.
  Stream<Fact<T>> get stream => registry.facts(fact: word.name).map(_decode);

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
final class FactEmitterOf<T> implements IHandle, IFactEmitter<T> {
  FactEmitterOf(this.raw, this._shape);

  /// The handle beneath: the registry's own, or a remote participant's.
  final IFactHandle raw;
  final Shape<T> _shape;

  /// As [RawFactEmitter.emit].
  @override
  bool emit(T payload, {String? id, Cause? cause}) =>
      raw.emit(_shape.toJson(payload), id: id, cause: cause);

  @override
  void dispose() => raw.dispose();
}
