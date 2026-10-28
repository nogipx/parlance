import 'dart:async';

import 'package:clock/clock.dart' show Clock;

import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/words.dart';
import '../view/view.dart';
import 'owner.dart';

/// A participant asked for what it may not do: a word outside its
/// vocabularies, a right it lacks, an act as someone else (SPEC §22.2).
final class NotPermitted extends StateError {
  NotPermitted(super.message);
}

/// What a participant may do beyond defining words in its vocabularies
/// (SPEC §22.2). Each check answers why not, or null to allow.
final class ParticipantRights {
  const ParticipantRights({this.define, this.produce, this.speakFor});

  /// Define [d], a word in its vocabularies: a further check (callers that
  /// name outsiders, a kind of word). Null: every word in its vocabularies.
  final String? Function(Principal who, Descriptor d)? define;

  /// Say [fact], an open fact another defined. Null: none.
  final String? Function(Principal who, String fact)? produce;

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
      : FactDescriptor(
          d.name,
          type: d.type,
          open: d.open,
          readers: read,
          meta: d.meta,
        );

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
/// calls what [who] may; it defines words only in its [vocabularies], and
/// writes and says them as [who]. The same whether the registry is in this
/// process ([LocalParticipant]) or across a connection.
///
/// `main` makes one per part and hands it over; the part never gets the
/// registry itself, so what its words' callers and readers say holds for
/// it.
abstract interface class IParticipant implements IRegistryView, IHandle {
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

  /// Who it speaks as.
  Principal get who;

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

  /// Calls [command] as [who]. A handler's nested call passes [cause]
  /// (`call.causeFor(who)`), so it follows from the call being served.
  /// [override] passes a guard's overridable denial, when [who]'s kind is
  /// one of the registry's overriders (SPEC §10).
  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
    bool override = false,
  });

  /// Defines a state of its own, with [who] its only writer; readers
  /// from [access] when [d] names none.
  IStateHandle defineState(StateDescriptor d);

  /// Defines a command of its own, served by [handler].
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
  });

  /// Defines a query of its own, answered by [handler] (SPEC §6.6).
  IHandle defineQuery(
    QueryDescriptor d,
    CommandHandler handler, {
    Availability? available,
  });

  /// Defines a fact of its own, with [who] its producer; readers from
  /// [access] when [d] names none.
  IFactHandle defineFact(FactDescriptor d);

  /// Another producer of an open [fact], as far as [rights] let it.
  IFactHandle producer(String fact);

  /// A guard (SPEC §10) on calls of its own commands only: what it judges
  /// is its own, never another's command.
  /// The registry knows it as `<who>#<id>`: refusals and call records
  /// name it so, and another participant's guard of the same [id] is
  /// another guard.
  IHandle addGuard(String id, GuardCheck check, {bool overridable = true});

  /// Registers a kind of entities it keeps (SPEC §3).
  IHandle registerKind(EntityKind kind);

  /// The entities of [kind], one it registered, changed.
  void entitiesChanged(String kind);

  /// The availability check of [command], its own, would answer otherwise
  /// now, though no tick says so: it reads what the registry does not keep.
  void availabilityChanged(String command);

  /// Runs [writes], its writes and facts committed as one tick.
  void batch(void Function() writes);

  /// Completes when the registry has done all it asked so far, and what it
  /// sees of the catalog, so [status] too, is as of then: in this process
  /// at once, across a connection after the host answered.
  Future<void> settle();

  /// Attaches [owners] (SPEC §22.3), each to the part of its name
  /// (`child(name)`), so causes, records and `explain` tell which owner did
  /// what; then writes what they have now, as one tick. The names are
  /// `main`'s; two owners of one name are refused. They go with it.
  void attach(Map<String, Owner> owners);

  /// Writes what every owner attached to it has now, as one tick.
  void sync();

  /// A part of it, named [name] (SPEC §22.3): `who.child(name)`
  /// (`studio@screen`), in the same vocabularies with the same rights, so
  /// what each part does is told as that part's in causes, records and
  /// `explain`. Its guards judge its own commands; a cause of this one
  /// passed to it is taken as its own. A part has no parts (`StateError`).
  IParticipant child(String name);

  /// Withdraws its owners, the last attached first, then everything it
  /// defined, registered and added, and its parts: a scope (a user's
  /// session, a feature) leaves nothing of itself, and its vocabularies are
  /// free again.
  @override
  void dispose();
}

/// A participant through typed words (SPEC §18): the word fixes the types.
extension TypedParticipant on IParticipant {
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

  final IParticipant participant;
  final IQueryWord<P, R> word;

  /// Defines it as the participant's own, served by [handler]; [askers],
  /// else who may read its words (`access.read`), else everyone.
  IHandle define(
    FutureOr<R> Function(QueryAsk<P> ask) handler, {
    Callers? askers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    Availability? available,
  }) => participant.defineQuery(
    word.describeWith(
      askers: participant.access.askersOf(askers),
      deadline: deadline,
      meta: meta,
    ),
    word.serve(handler),
    available: available,
  );

  /// Asks it as the participant; asking again asks again.
  Future<CallResult<R>> ask(P params, {Cause? cause}) async => word.answer(
    await participant.call(word.name, word.params.toJson(params), cause: cause),
  );

  WordStatus get status => participant.status(word.name);
  Stream<WordStatus> get statusChanges => participant.statusChanges(word.name);
}

/// A state as a participant has it, typed.
final class ParticipantStateOf<T> {
  ParticipantStateOf._(this.participant, this.word);

  final IParticipant participant;
  final IStateWord<T> word;

  /// Defines it as the participant's own.
  StateWriterOf<T> define({
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => StateWriterOf(
    participant.defineState(
      StateDescriptor(
        word.name,
        type: word.shape.type,
        key: word.key,
        readers: readers,
        meta: meta,
      ),
    ),
    word.shape,
  );

  /// Its value (of [key]) now.
  T? read({String? key}) => word.decode(participant.read(word.name, key: key));

  /// Every value, by key; a null one too, of a state that may be null.
  Map<String?, T> readAll() => {
    for (final e in participant.readAll(word.name).entries)
      if (e.value != null || null is T) e.key: word.shape.fromJson(e.value),
  };

  /// Its value now, then on every change.
  Stream<T?> watch({String? key}) =>
      participant.watch(word.name, key: key).map(word.decode);

  /// Its value (of [key]) as the core reads a cell (SPEC §21.6), here or
  /// across a connection; over one, another's state is there while it is
  /// watched.
  IStateReader<T> reader({String? key}) => _ParticipantReader(this, key);

  WordStatus get status => participant.status(word.name);
  Stream<WordStatus> get statusChanges => participant.statusChanges(word.name);
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

  final IParticipant participant;
  final ICommandWord<P, R> word;

  /// Defines it as the participant's own, served by [handler] (SPEC §6.2);
  /// [callers], else the participant's default (`access.call`). A word
  /// that only answers is a query ([IQueryWord]), not a command.
  IHandle define(
    FutureOr<R> Function(CommandCallOf<P> call) handler, {
    Callers? callers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    Availability? available,
  }) {
    Object? answer(R value) => word.returns?.toJson(value);
    return participant.defineCommand(
      CommandDescriptor(
        word.name,
        params: word.params.type,
        returns: word.returns?.type,
        callers: participant.access.callersOf(word.name, callers),
        deadline: deadline,
        meta: meta,
      ),
      (c) {
        final out = handler(
          CommandCallOf(
            c,
            word.params.fromJson(c.params),
            servedBy: participant.who,
          ),
        );
        return out is Future<R> ? out.then(answer) : answer(out);
      },
      available: available,
    );
  }

  /// Calls it with [params] as the participant; [override] as
  /// [IParticipant.call] says.
  Future<CallResult<R>> call(
    P params, {
    String? id,
    Cause? cause,
    bool override = false,
  }) async => word.answer(
    await participant.call(
      word.name,
      word.params.toJson(params),
      id: id,
      cause: cause,
      override: override,
    ),
  );

  /// Calls as the core asks a port (SPEC §21.6): the answer of a done
  /// call, else [CallNotDone] with how it ended.
  ICommandCaller<P, R> get caller => _ParticipantCaller(this);

  WordStatus get status => participant.status(word.name);
  Stream<WordStatus> get statusChanges => participant.statusChanges(word.name);
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

  final IParticipant participant;
  final IFactWord<T> word;

  /// Defines it as the participant's own.
  FactEmitterOf<T> define({
    bool open = false,
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => FactEmitterOf(
    participant.defineFact(
      FactDescriptor(
        word.name,
        type: word.shape.type,
        open: open,
        readers: readers,
        meta: meta,
      ),
    ),
    word.shape,
  );

  /// Another producer of it, an open fact.
  FactEmitterOf<T> producer() =>
      FactEmitterOf(participant.producer(word.name), word.shape);

  Fact<T> _decode(FactMessage m) => Fact(word.shape.fromJson(m.payload), m);

  /// Those said from now on.
  Stream<Fact<T>> get stream => participant.facts(word.name).map(_decode);

  /// Its payloads as the core hears a signal (SPEC §21.6).
  IFactListener<T> get listener => _ParticipantListener(this);

  /// The last [count] the registry keeps, oldest first.
  Future<List<Fact<T>>> recent(int count) async => [
    for (final m in await participant.recent(word.name, count)) _decode(m),
  ];

  WordStatus get status => participant.status(word.name);
  Stream<WordStatus> get statusChanges => participant.statusChanges(word.name);
}

final class _ParticipantListener<T> implements IFactListener<T> {
  _ParticipantListener(this._fact);
  final ParticipantFactOf<T> _fact;

  @override
  Stream<T> get stream => _fact.stream.map((f) => f.payload);
}
