import 'dart:async';

import 'package:clock/clock.dart' show Clock;

import '../registry/cause.dart';
import '../registry/compat.dart' show WordBreak;
import '../registry/descriptors.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/shapes.dart';
import '../registry/words.dart';
import '../view/view.dart';
import 'owner.dart';

/// A participant asked for what it may not do: a word outside its
/// vocabularies, a right it lacks, an act as someone else (SPEC §22.2).
final class NotPermitted extends StateError {
  NotPermitted(super.message);

  @override
  String toString() => 'NotPermitted: $message';
}

/// What a participant may do beyond defining words in its vocabularies
/// (SPEC §22.2). Each check answers why not, or null to allow.
final class ParticipantRights {
  const ParticipantRights({this.define, this.speakFor});

  /// Define [d], a word in its vocabularies: a further check (callers that
  /// name outsiders, a kind of word). Null: every word in its vocabularies.
  final String? Function(Principal who, Descriptor d)? define;

  /// Say [fact] on behalf of [by]: its cause is theirs, and so are the
  /// rights of what follows from it. Null: no one.
  final String? Function(Principal who, Principal by, String fact)? speakFor;

  /// Defines in its vocabularies, and nothing more.
  static const none = ParticipantRights();
}

/// Who may read and call a participant's words when a word does not say
/// (SPEC §22.2): its states' and facts' `readers`, its commands' `callers`.
/// A word's own replaces it whole; nothing merges.
final class WordAccess {
  const WordAccess({this.read, this.call});

  /// Readers of its states and facts; null: everyone.
  final Callers? read;

  /// Callers of its commands; null: each command says.
  final Callers? call;

  static const none = WordAccess();

  /// This, where it says nothing, then [fallback].
  WordAccess or(WordAccess fallback) =>
      WordAccess(read: read ?? fallback.read, call: call ?? fallback.call);

  /// [d] with [read] as its readers when it names none.
  StateDescriptor state(StateDescriptor d) => d.readers != null || read == null
      ? d
      : StateDescriptor(
          d.name,
          type: d.type,
          key: d.key,
          readers: read,
          meta: d.meta,
        );

  /// [d] with [read] as its readers when it names none.
  FactDescriptor fact(FactDescriptor d) => d.readers != null || read == null
      ? d
      : FactDescriptor(d.name, type: d.type, readers: read, meta: d.meta);

  /// [callers], else [read], else everyone: who may ask a query, as who
  /// may read a state.
  Callers askersOf(Callers? callers) =>
      callers ?? read ?? const Callers({'*': Access.allow});

  /// [callers], else [call]; a command with neither is refused at once.
  Callers callersOf(String command, Callers? callers) =>
      callers ??
      call ??
      (throw ArgumentError(
        '$command names no callers, and its participant no default: '
        'say who may call it',
      ));
}

/// A part of the app as it speaks (SPEC §22): it sees the registry only
/// through this, as one principal, [who]. It reads, watches, hears and
/// calls what [who] may (as the view it is, [IRegistryView]); it defines
/// words only in its vocabularies, through typed words
/// ([TypedParticipant]), and writes and says them as [who]. The same
/// whether the registry is in this process or across a connection.
///
/// `main` makes one per part and hands it over; the part never gets the
/// registry itself, so what its words' callers and readers say holds for
/// it. Frozen (`schema.dart`): what it shows is never taken away; only the
/// library makes one, so it may grow. Not to be implemented: a test gives
/// a stand-in of a client (`I<Class>Client`), not of this.
abstract interface class IParticipant implements IHandle {
  /// Who it speaks as.
  Principal get who;

  /// Runs [writes], its writes and facts committed as one tick.
  void batch(void Function() writes);

  /// Completes when the registry has done all it asked so far, what it
  /// sees of the catalog (so [status] too) and of the states is as of
  /// then, and its listeners were told: what a test waits for after it
  /// acted, in place of a delay. In this process after a turn of the event
  /// loop, across a connection once its copy reached the host.
  Future<void> settle();

  /// Attaches [owners] (SPEC §22.3), each to the part named by its
  /// vocabulary (`house@house`), so causes, records and `explain` tell
  /// which owner did what; one of no words (a rule of the whole, a guard)
  /// speaks as the participant. Two owners of one vocabulary are refused.
  /// They go with it.
  /// Completes when the registry has their words and what they set:
  /// at once in the host's process, across a connection when the host
  /// answered (what it refused told to its errors by then).
  Future<void> attach(Iterable<IOwner> owners);

  /// Writes what every owner attached to it has now (what each
  /// `follow`s), as one tick.
  void sync();

  /// A part of it, named [name] (SPEC §22.3): `who.child(name)`
  /// (`home@house`), in the same vocabularies with the same rights, so
  /// what each part does is told as that part's in causes, records and
  /// `explain`. A part has no parts (`StateError`).
  IParticipant child(String name);

  /// Withdraws its owners, the last attached first, then everything it
  /// defined, registered and added, and its parts: a scope (a user's
  /// session, a feature) leaves nothing of itself, and its vocabularies are
  /// free again.
  @override
  void dispose();
}

/// A participant as the library and its tools have it: all it does by
/// name and descriptor, beside its typed words. Every participant the
/// library makes is one ([IParticipantRaw.raw]). Not frozen: it changes
/// as the library does.
abstract interface class IRawParticipant
    implements IParticipant, IRegistryView {
  /// The catalog as it sees it (SPEC §22): the words, what it may call and
  /// read, what cannot run now; what an agent or an editor shows of it.
  Future<Map<String, Object?>> describe();

  /// Why [state] (of [key]) is as it is (SPEC §9): its value, its last
  /// change, the calls that led to it. Refused ([NotPermitted]) when it may
  /// not read it; counted as its use of the word (§6.8).
  Future<Explanation> explain(String state, {String? key});

  /// Told when the catalog it sees changes: a word came or went, a kind's
  /// entities changed.
  Stream<void> get catalogChanges;

  /// The first words of the names it may define: `orders` for
  /// `orders.cancel` and `orders.list.page`.
  Set<String> get vocabularies;

  /// Who may read and call its words when a word does not say.
  WordAccess get access;

  /// Where it reads the time: the registry's clock in this process.
  Clock get clock;

  /// The value of [state] (of [key]) now, then on every change; null
  /// alone when [who] may not read it.
  Stream<Object?> watch(String state, {String? key});

  /// [watch] as [shape] has it (SPEC §18).
  Stream<T?> watchAs<T>(String state, Shape<T> shape, {String? key});

  /// Calls [command] as [who]. A handler's nested call passes [cause]
  /// (`call.causeFor(who)`), so it follows from the call being served.
  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
  });

  /// [call] with [params] as [shape] has them (SPEC §18).
  @override
  Future<CallResult<Object?>> callAs(
    String command,
    Object? params,
    Shape<Object?> shape, {
    String? id,
    Cause? cause,
  });

  /// Defines a state of its own, with [who] its only writer; readers
  /// from [access] when [d] names none. Given its values' [shape], its
  /// handle takes Dart values when the registry keeps them so (SPEC §18).
  IStateHandle defineState(StateDescriptor d, {Shape<Object?>? shape});

  /// Defines a command of its own, served by [handler]. Given the shapes
  /// of its [params] and what it [returns], its handler gets and answers
  /// Dart values where the registry keeps them so (SPEC §18).
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  });

  /// Defines a query of its own, answered by [handler] (SPEC §6.6), its
  /// shapes as [defineCommand]'s.
  IHandle defineQuery(
    QueryDescriptor d,
    CommandHandler handler, {
    Availability? available,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  });

  /// Defines a fact of its own, with [who] its producer; readers from
  /// [access] when [d] names none. Given its payloads' [shape], its handle
  /// takes Dart values when the registry keeps them so (SPEC §18).
  IFactHandle defineFact(FactDescriptor d, {Shape<Object?>? shape});

  /// A guard (SPEC §10) on calls of its own commands only: what it judges
  /// is its own, never another's command.
  /// The registry knows it as `<who>#<id>`: refusals and call records
  /// name it so, and another participant's guard of the same [id] is
  /// another guard.
  IHandle addGuard(String id, GuardCheck check);

  /// Registers a kind of entities it keeps (SPEC §3).
  IHandle registerKind(EntityKind kind);

  /// The entities of [kind], one it registered, changed.
  void entitiesChanged(String kind);

  /// The availability check of [command], its own, would answer otherwise
  /// now, though no tick says so: it reads what the registry does not keep.
  void availabilityChanged(String command);

  /// The availability checks of all its commands may answer otherwise
  /// now: each is asked again, and a status told where it changed.
  void availabilityMayHaveChanged();

  @override
  IRawParticipant child(String name);

  /// The participant this is a part of, or itself when it is no part: what
  /// a guard of every command it serves is added on.
  IRawParticipant get whole;
}

/// [answer], as a handler served by [part] gave it; its owner told once
/// it is given.
FutureOr<R> _served<R>(IParticipant part, FutureOr<R> answer) {
  if (answer is Future<R>) {
    return answer.whenComplete(() => ownerServed(part));
  }
  ownerServed(part);
  return answer;
}

/// Every participant is raw underneath ([IRawParticipant]): the library's
/// way in, and its tools'.
extension IParticipantRaw on IParticipant {
  IRawParticipant get raw => this as IRawParticipant;
}

/// The one door generated code reaches the words by (SPEC §23): the owner
/// base defines and serves through it, the client reads, watches, calls
/// and hears. It is the generator's contract, frozen with `schema.dart`,
/// and not a way to write by hand: a part uses a client, an owner its
/// base.
final class GeneratedWords {
  GeneratedWords._(this._resolve, this._owner);

  /// The words through [participant].
  static GeneratedWords of(IParticipant participant) {
    final raw = participant.raw;
    return GeneratedWords._(() => raw, null);
  }

  /// The words through the participant [owner] is attached to, found when
  /// they are used: an owner's client, made in its constructor. Used
  /// before it is attached, a read or a call throws a [StateError]; a
  /// stream waits until it is listened to ([later]).
  static GeneratedWords ofOwner(IOwner owner) =>
      GeneratedWords._(() => OwnerParticipant(owner).participant.raw, owner);

  final IRawParticipant Function() _resolve;
  final IOwner? _owner;

  ParticipantStateOf<T> state<T>(IStateWord<T> word) => _resolve().state(word);
  ParticipantCommandOf<P, R> command<P, R>(ICommandWord<P, R> word) =>
      _resolve().command(word);
  ParticipantFactOf<T> fact<T>(IFactWord<T> word) => _resolve().fact(word);
  ParticipantQueryOf<P, R> query<P, R>(IQueryWord<P, R> word) =>
      _resolve().query(word);

  /// The state [word] as a part reads it ([IStateOf]).
  IStateOf<T> stateOf<T>(IStateWord<T> word) => _StateOf(this, word);

  /// The keyed state [word] as a part reads it ([IKeyedOf]).
  IKeyedOf<T> keyedOf<T>(IStateWord<T> word) => _KeyedOf(this, word);

  /// The fact [word] as a part hears it ([IFactOf]).
  IFactOf<T> factOf<T>(IFactWord<T> word) => _FactOf(this, word);

  /// [make]'s stream, made when it is listened to: an owner's client hands
  /// out its streams before the owner is attached, and its tools listen
  /// to them once it is.
  Stream<T> later<T>(Stream<T> Function() make) =>
      _owner == null ? make() : _Later(make);

  /// Tells the registry the code was built against [words] (SPEC §6.9):
  /// an owner's client once the owner is attached.
  void builtAgainst(Iterable<IWord> words, {String? from}) {
    if (_owner case final o?) {
      OwnerParticipant(
        o,
      ).whenAttached((p) => p.raw.builtAgainst(words, from: from));
    } else {
      _resolve().builtAgainst(words, from: from);
    }
  }

  /// Whether [word] is there now, as this code was built against it.
  WordStatus status(IWord word) => wordStatus(_resolve(), word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) =>
      later(() => wordStatusChanges(_resolve(), word));

  /// Each of [words] there but not as this code was built against.
  Map<String, List<WordBreak>> mismatches(Iterable<IWord> words) =>
      wordMismatches(_resolve(), words);
}

final class _StateOf<T> implements IStateOf<T> {
  _StateOf(this._w, this._word);
  final GeneratedWords _w;
  final IStateWord<T> _word;

  @override
  T? get value => _w.state(_word).read();

  @override
  Stream<T?> get changes => _w.later(() => _w.state(_word).watch());

  @override
  String toString() => '${_word.name} = $value';
}

final class _KeyedOf<T> implements IKeyedOf<T> {
  _KeyedOf(this._w, this._word);
  final GeneratedWords _w;
  final IStateWord<T> _word;

  @override
  T? of(String key) => _w.state(_word).read(key: key);

  @override
  Map<String, T> get all => {
    for (final MapEntry(:key, :value) in _w.state(_word).readAll().entries)
      ?key: value,
  };

  @override
  Stream<T?> changesOf(String key) =>
      _w.later(() => _w.state(_word).watch(key: key));

  @override
  String toString() => '${_word.name} = $all';
}

final class _FactOf<T> implements IFactOf<T> {
  _FactOf(this._w, this._word);
  final GeneratedWords _w;
  final IFactWord<T> _word;

  @override
  Stream<T> get stream =>
      _w.later(() => _w.fact(_word).stream.map((f) => f.payload));

  @override
  Stream<Fact<T>> get facts => _w.later(() => _w.fact(_word).stream);

  @override
  String toString() => _word.name;
}

/// A stream made anew for each listener, when it listens.
final class _Later<T> extends Stream<T> {
  _Later(this._make);
  final Stream<T> Function() _make;

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _make().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

/// A participant through typed words (SPEC §18): the word fixes the types.
/// The library's and its tools'; generated code reaches it through
/// [GeneratedWords].
extension TypedParticipant on IRawParticipant {
  ParticipantStateOf<T> state<T>(IStateWord<T> word) =>
      ParticipantStateOf._(this, word);
  ParticipantCommandOf<P, R> command<P, R>(ICommandWord<P, R> word) =>
      ParticipantCommandOf._(this, word);
  ParticipantFactOf<T> fact<T>(IFactWord<T> word) =>
      ParticipantFactOf._(this, word);
  ParticipantQueryOf<P, R> query<P, R>(IQueryWord<P, R> word) =>
      ParticipantQueryOf._(this, word);
}

/// A query as a participant has it, typed (SPEC §6.6).
final class ParticipantQueryOf<P, R> {
  ParticipantQueryOf._(this.participant, this.word);

  final IRawParticipant participant;
  final IQueryWord<P, R> word;

  /// Defines it as the participant's own, answered by [handler] of its
  /// params (SPEC §23.4); [askers], else who may read its words
  /// (`access.read`), else everyone. [available] says why it cannot be
  /// asked now, or null.
  IHandle serve(
    FutureOr<R> Function(P params) handler, {
    Callers? askers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    String? Function()? available,
  }) => define(
    (a) => _served(participant, handler(a.params)),
    askers: askers,
    deadline: deadline,
    meta: meta,
    available: available,
  );

  /// Asks it as the participant; asking again asks again.
  Future<CallResult<R>> ask(P params) => askFrom(params);

  /// As the code was built against it (SPEC §6.5): [WordMismatch] when not.
  WordStatus get status => wordStatus(participant, word);
  Stream<WordStatus> get statusChanges => wordStatusChanges(participant, word);
}

/// A state as a participant has it, typed.
final class ParticipantStateOf<T> {
  ParticipantStateOf._(this.participant, this.word);

  final IRawParticipant participant;
  final IStateWord<T> word;

  /// Defines it as the participant's own.
  IStateWriterOf<T> define({
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => StateWriterOf(
    participant.raw.defineState(
      StateDescriptor(
        word.name,
        type: word.shape.type,
        key: word.key,
        readers: readers,
        meta: meta,
      ),
      shape: word.shape,
    ),
    word.shape,
  );

  /// Its value (of [key]) now.
  T? read({String? key}) => participant.readAs(word.name, word.shape, key: key);

  /// Every value, by key; a null one too, of a state that may be null.
  Map<String?, T> readAll() => {
    for (final e in participant.readAll(word.name).entries)
      if (e.value != null || null is T) e.key: word.shape.fromJson(e.value),
  };

  /// Its value now, then on every change.
  Stream<T?> watch({String? key}) =>
      participant.raw.watchAs(word.name, word.shape, key: key);

  /// Its value (of [key]) as the core reads a cell (SPEC §21.6), here or
  /// across a connection; over one, another's state is there while it is
  /// watched.
  IStateReader<T> reader({String? key}) => _ParticipantReader(this, key);

  /// As the code was built against it (SPEC §6.5): [WordMismatch] when not.
  WordStatus get status => wordStatus(participant, word);
  Stream<WordStatus> get statusChanges => wordStatusChanges(participant, word);
}

final class _ParticipantReader<T> implements IStateReader<T> {
  _ParticipantReader(this._state, this._key);
  final ParticipantStateOf<T> _state;
  final String? _key;

  @override
  T? get value => _state.read(key: _key);

  /// Whether there is a value, a null one of a state that may be null too.
  @override
  bool get has =>
      value != null ||
      _state.participant.readAll(_state.word.name).containsKey(_key);

  @override
  Stream<T?> watch() => _state.watch(key: _key);
}

/// A command as a participant has it, typed.
final class ParticipantCommandOf<P, R> {
  ParticipantCommandOf._(this.participant, this.word);

  final IRawParticipant participant;
  final ICommandWord<P, R> word;

  /// Defines it as the participant's own (SPEC §6.2), served by [handler]
  /// of its params (SPEC §23.4): what the handler does follows from the
  /// call. [callers], else the participant's default (`access.call`);
  /// [available] says why it cannot run now, or null. A word that only
  /// answers is a query ([IQueryWord]), not a command.
  IHandle serve(
    FutureOr<R> Function(P params) handler, {
    Callers? callers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    String? Function()? available,
  }) => define(
    (c) => _served(participant, handler(c.params)),
    callers: callers,
    deadline: deadline,
    meta: meta,
    available: available,
  );

  /// Calls it with [params] as the participant, under [id] when given (a
  /// retry with the same id runs once).
  Future<CallResult<R>> call(P params, {String? id}) =>
      callFrom(params, id: id);

  /// Calls as the core asks a port (SPEC §21.6): the answer of a done
  /// call, else [CallNotDone] with how it ended.
  ICommandCaller<P, R> get caller => _ParticipantCaller(this);

  /// As the code was built against it (SPEC §6.5): [WordMismatch] when not.
  WordStatus get status => wordStatus(participant, word);
  Stream<WordStatus> get statusChanges => wordStatusChanges(participant, word);
}

final class _ParticipantCaller<P, R> implements ICommandCaller<P, R> {
  _ParticipantCaller(this._command);
  final ParticipantCommandOf<P, R> _command;

  @override
  Future<R> call(P params) async {
    final r = await _command.call(params);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }
}

/// A fact as a participant has it, typed.
final class ParticipantFactOf<T> {
  ParticipantFactOf._(this.participant, this.word);

  final IRawParticipant participant;
  final IFactWord<T> word;

  /// Defines it as the participant's own.
  IFactEmitterOf<T> define({
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => FactEmitterOf(
    participant.raw.defineFact(
      FactDescriptor(
        word.name,
        type: word.shape.type,
        readers: readers,
        meta: meta,
      ),
      shape: word.shape,
    ),
    word.shape,
  );

  Fact<T> _decode(FactMessage m) => Fact(word.shape.fromJson(m.payload), m);

  /// Those said from now on.
  Stream<Fact<T>> get stream =>
      participant.factsAs(word.name, word.shape).map((f) => Fact(f.$1, f.$2));

  /// Its payloads as the core hears a signal (SPEC §21.6).
  IFactListener<T> get listener => _ParticipantListener(this);

  /// The last [count] the registry keeps, oldest first.
  Future<List<Fact<T>>> recent(int count) async => [
    for (final m in await participant.recent(word.name, count)) _decode(m),
  ];

  /// As the code was built against it (SPEC §6.5): [WordMismatch] when not.
  WordStatus get status => wordStatus(participant, word);
  Stream<WordStatus> get statusChanges => wordStatusChanges(participant, word);
}

final class _ParticipantListener<T> implements IFactListener<T> {
  _ParticipantListener(this._fact);
  final ParticipantFactOf<T> _fact;

  @override
  Stream<T> get stream => _fact.stream.map((f) => f.payload);
}

/// What the library and its tests do with a query by its ask: not frozen.
extension RawQueryOf<P, R> on ParticipantQueryOf<P, R> {
  /// Defines it, served by [handler] of its ask (its params, who asks).
  IHandle define(
    FutureOr<R> Function(QueryAsk<P> ask) handler, {
    Callers? askers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    Availability? available,
  }) {
    final p = participant.raw;
    return p.defineQuery(
      word.describeWith(
        askers: p.access.askersOf(askers),
        deadline: deadline,
        meta: meta,
      ),
      word.serve(handler),
      available: available,
      params: word.params,
      returns: word.returns,
    );
  }

  /// Asks it, following from [cause] when given.
  Future<CallResult<R>> askFrom(P params, {Cause? cause}) async => word.answer(
    await participant.raw.callAs(word.name, params, word.params, cause: cause),
  );
}

/// What the library and its tests do with a command by its call: not
/// frozen.
extension RawCommandOf<P, R> on ParticipantCommandOf<P, R> {
  /// Defines it, served by [handler] of its call (its params, its cause).
  IHandle define(
    FutureOr<R> Function(CommandCallOf<P> call) handler, {
    Callers? callers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    Availability? available,
  }) {
    final p = participant.raw;
    return p.defineCommand(
      CommandDescriptor(
        word.name,
        params: word.params.type,
        returns: word.returns?.type,
        callers: p.access.callersOf(word.name, callers),
        deadline: deadline,
        meta: meta,
      ),
      word.serve(handler, servedBy: p.who),
      available: available,
      params: word.params,
      returns: word.returns,
    );
  }

  /// Calls it, following from [cause] when given.
  Future<CallResult<R>> callFrom(P params, {String? id, Cause? cause}) async =>
      word.answer(
        await participant.raw.callAs(
          word.name,
          params,
          word.params,
          id: id,
          cause: cause,
        ),
      );
}
