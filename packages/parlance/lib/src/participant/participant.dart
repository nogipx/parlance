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

  /// Define the word [call] names, one in its vocabularies: a further
  /// check (readers or callers that name outsiders). Null: every word in
  /// its vocabularies.
  final String? Function(DefineCall call)? define;

  /// Say a fact on behalf of another ([SpeakForCall]): its cause is
  /// theirs, and so are the rights of what follows from it. Null: no one.
  final String? Function(SpeakForCall call)? speakFor;

  /// Defines in its vocabularies, and nothing more.
  static const none = ParticipantRights();
}

/// What a word is: a state, a command, a query or a fact.
enum WordRole { state, command, query, fact }

/// A word a participant asks to define, as its rights judge it
/// ([ParticipantRights.define]): who asks, the word and what it is, and
/// who it says may read it or call it. What a check is told may grow; a
/// check written now keeps working.
final class DefineCall {
  DefineCall._(this.by, this.word, this.role, {this.readers, this.callers});

  /// The participant that defines it.
  final Principal by;

  /// Its name.
  final String word;

  /// What it is.
  final WordRole role;

  /// Who may read a state or hear a fact; null for a command or a query,
  /// or when it names none.
  final Callers? readers;

  /// Who may call a command or ask a query; null for a state or a fact.
  final Callers? callers;
}

/// A fact a participant asks to say on behalf of another, as its rights
/// judge it ([ParticipantRights.speakFor]). What a check is told may grow.
final class SpeakForCall {
  SpeakForCall._(this.speaker, this.by, this.fact);

  /// The participant that says it.
  final Principal speaker;

  /// On whose behalf it is said, as `say(by:)` names them.
  final Principal by;

  /// The fact.
  final String fact;
}

/// [speaker] saying [fact] on behalf of [by], as its rights judge it: the
/// library's.
SpeakForCall speakForCallOf(Principal speaker, Principal by, String fact) =>
    SpeakForCall._(speaker, by, fact);

/// [d] as [who]'s rights judge it: the library's.
DefineCall defineCallOf(Principal who, Descriptor d) => switch (d) {
  StateDescriptor(:final readers) => DefineCall._(
    who,
    d.name,
    WordRole.state,
    readers: readers,
  ),
  FactDescriptor(:final readers) => DefineCall._(
    who,
    d.name,
    WordRole.fact,
    readers: readers,
  ),
  CommandDescriptor(:final callers) => DefineCall._(
    who,
    d.name,
    WordRole.command,
    callers: callers,
  ),
  QueryDescriptor(:final callers) => DefineCall._(
    who,
    d.name,
    WordRole.query,
    callers: callers,
  ),
};

/// Who may read and call a participant's words when a word does not say
/// (SPEC §22.2): its states' and facts' `readers`, its commands' `callers`.
/// A word's own replaces it whole; nothing merges.
final class WordAccess {
  const WordAccess({this.readers, this.callers});

  /// Readers of its states and facts; null: everyone.
  final Callers? readers;

  /// Callers of its commands; null: each command says.
  final Callers? callers;

  static const none = WordAccess();
}

/// What the library does with a participant's [WordAccess] as it defines
/// its words: not the app's.
extension WordAccessOf on WordAccess {
  /// [d] with [readers] as its readers when it names none.
  StateDescriptor state(StateDescriptor d) =>
      d.readers != null || readers == null
      ? d
      : StateDescriptor(
          d.name,
          type: d.type,
          key: d.key,
          readers: readers,
          meta: d.meta,
        );

  /// [d] with [readers] as its readers when it names none.
  FactDescriptor fact(FactDescriptor d) => d.readers != null || readers == null
      ? d
      : FactDescriptor(d.name, type: d.type, readers: readers, meta: d.meta);

  /// [callers], else [readers], else everyone: who may ask a query, as who
  /// may read a state.
  Callers askersOf(Callers? callers) => callers ?? readers ?? Callers.anyone;

  /// [callers], else [this.callers]; a command with neither is refused at once.
  Callers callersOf(String command, Callers? callers) =>
      callers ??
      this.callers ??
      (throw ArgumentError(
        '$command names no callers, and its participant no default: '
        'say who may call it',
      ));
}

/// A part of the app as it speaks (SPEC §22): it sees the registry only
/// through this, as one principal, [who]. It reads, watches, hears and
/// calls what [who] may (as the view it is, [IRegistryView]); it defines
/// words only in its vocabularies, through its owners, and writes and
/// says them as [who]. The same
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

  /// Writes what every owner attached to it has now (what each
  /// `follow`s), as one tick: for a host whose model tells it changed
  /// (`controller.addListener(p.sync)`) where an owner's `follow(on:)`
  /// cannot hear it.
  void sync();

  /// Withdraws its owners, the last attached first, then everything it
  /// defined, registered and added, its owners' too: a scope (a user's
  /// session, a feature) leaves nothing of itself, and its vocabularies are
  /// free again.
  @override
  void dispose();
}

/// A participant as the library and its tools have it: all it does by
/// name and descriptor, beside its typed words. Every participant the
/// library makes is one ([RawAccess.raw]). Not frozen: it changes
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

  /// Told when the catalog it sees changes: a word came or went, the
  /// choices of a name changed.
  Stream<void> get catalogChanges;

  /// Its vocabularies' names, the first word of the names it may define:
  /// `orders` for `orders.cancel`.
  Set<String> get vocabularyNames;

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

  /// Defines a fact of its own, with [who] its owner; readers from
  /// [access] when [d] names none. Given its payloads' [shape], its handle
  /// takes Dart values when the registry keeps them so (SPEC §18).
  IFactHandle defineFact(FactDescriptor d, {Shape<Object?>? shape});

  /// A guard (SPEC §10) on calls of its own commands only: what it judges
  /// is its own, never another's command.
  /// The registry knows it as `<who>#<id>`: refusals and call records
  /// name it so, and another participant's guard of the same [id] is
  /// another guard.
  IHandle addGuard(String id, GuardCheck check);

  /// Gives [choices] (SPEC §3): what a `ChoiceType` of their name holds a
  /// value to.
  IHandle addChoices(Choices choices);

  /// The choices of [name], ones it gives, changed.
  void choicesChanged(String name);

  /// The availability check of [command], its own, would answer otherwise
  /// now, though no tick says so: it reads what the registry does not keep.
  void availabilityChanged(String command);

  /// The availability checks of all its commands may answer otherwise
  /// now: each is asked again, and a status told where it changed.
  void availabilityMayHaveChanged();

  /// It for its owner [name] (SPEC §22.3): speaking as `who.ofOwner(name)`
  /// (`home@house`), in the same vocabularies with the same rights, so
  /// what each owner does is told as that owner's in causes, records and
  /// `explain`. One of an owner has no owners (`StateError`). The library
  /// names an owner by its vocabulary.
  IRawParticipant ofOwner(String name);

  /// The participant this one speaks for an owner of, or itself when it
  /// speaks for none: what a guard of every command it serves is added
  /// on.
  IRawParticipant get whole;
}

/// [answer], as a handler served by [p] gave it; its owner told once
/// it is given.
FutureOr<R> _served<R>(IParticipant p, FutureOr<R> answer) {
  if (answer is Future<R>) {
    return answer.whenComplete(() => ownerServed(p));
  }
  ownerServed(p);
  return answer;
}

/// Every participant is raw underneath ([IRawParticipant]): the library's
/// way in, and its tools'.
extension RawAccess on IParticipant {
  IRawParticipant get raw => this as IRawParticipant;
}

/// The one door typed words are reached by (SPEC §23): the owner base
/// defines and serves through it, the client reads, watches, calls and
/// hears. It is the generator's contract, frozen with `schema.dart`, and
/// not a way to write an app by hand: a part uses a client, an owner its
/// base. A tool with words named at run time (`StateWordOf`) takes it too.
final class GeneratedWords {
  GeneratedWords._(this._resolve, this._owner);

  /// The words through [participant].
  factory GeneratedWords(IParticipant participant) {
    final raw = participant.raw;
    return GeneratedWords._(() => raw, null);
  }

  /// The words through the participant [owner] is attached to, found when
  /// they are used: an owner's client, made in its constructor. Used
  /// before it is attached, a read or a call throws a [StateError]; a
  /// stream waits until it is listened to ([later]).
  static GeneratedWords of(IOwner owner) =>
      GeneratedWords._(() => OwnerParticipant(owner).participant.raw, owner);

  final IRawParticipant Function() _resolve;
  final IOwner? _owner;

  /// The state [word], for the owner base to define.
  GeneratedState<T> state<T>(IStateWord<T> word) =>
      GeneratedState._(_resolve(), word);

  /// The command [word], for the owner base to serve and the client to
  /// call.
  GeneratedCommand<P, R> command<P, R>(ICommandWord<P, R> word) =>
      GeneratedCommand._(_resolve(), word);

  /// The fact [word], for the owner base to define.
  GeneratedFact<T> fact<T>(IFactWord<T> word) =>
      GeneratedFact._(_resolve(), word);

  /// The query [word], for the owner base to serve and the client to ask.
  GeneratedQuery<P, R> query<P, R>(IQueryWord<P, R> word) =>
      GeneratedQuery._(_resolve(), word);

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
  T? get value => _w._resolve().readAs(_word.name, _word.shape);

  @override
  Stream<T?> get changes =>
      _w.later(() => _w._resolve().watchAs(_word.name, _word.shape));

  @override
  String toString() => '${_word.name} = $value';
}

final class _KeyedOf<T> implements IKeyedOf<T> {
  _KeyedOf(this._w, this._word);
  final GeneratedWords _w;
  final IStateWord<T> _word;

  @override
  T? of(String key) => _w._resolve().readAs(_word.name, _word.shape, key: key);

  @override
  Map<String, T> get all => {
    for (final MapEntry(:key, :value)
        in _w._resolve().readAll(_word.name).entries)
      if (key != null && (value != null || null is T))
        key: _word.shape.fromJson(value),
  };

  @override
  Iterable<String> get keys => all.keys;

  @override
  Stream<T?> changesOf(String key) =>
      _w.later(() => _w._resolve().watchAs(_word.name, _word.shape, key: key));

  @override
  Stream<Map<String, T>> get changes => _w.later(
    () => Stream.multi((c) {
      c.add(all);
      final sub = _w._resolve().changes({_word.name}).listen((_) => c.add(all));
      c.onCancel = sub.cancel;
    }),
  );

  @override
  String toString() => '${_word.name} = $all';
}

final class _FactOf<T> implements IFactOf<T> {
  _FactOf(this._w, this._word);
  final GeneratedWords _w;
  final IFactWord<T> _word;

  @override
  Stream<T> get payloads => facts.map((f) => f.payload);

  @override
  Stream<Fact<T>> get facts => _w.later(
    () => _w
        ._resolve()
        .factsAs(_word.name, _word.shape)
        .map((f) => factIn(f.$1, f.$2)),
  );

  @override
  Future<List<Fact<T>>> recent(int count) async => [
    for (final m in await _w._resolve().recent(_word.name, count))
      factIn(_word.shape.fromJson(m.payload), m),
  ];

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

/// A state as the generated owner base defines it ([GeneratedWords.state]):
/// the generator's contract, not a way to write by hand.
final class GeneratedState<T> {
  GeneratedState._(this._p, this._word);

  final IRawParticipant _p;
  final IStateWord<T> _word;

  /// Defines it as the participant's own; [readers], else who may read its
  /// words (`access.readers`), else everyone.
  IStateWriterOf<T> define({
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => StateWriterOf(
    _p.defineState(
      StateDescriptor(
        _word.name,
        type: _word.shape.type,
        key: _word.key,
        readers: readers,
        meta: meta,
      ),
      shape: _word.shape,
    ),
    _word.shape,
  );
}

/// A fact as the generated owner base defines it ([GeneratedWords.fact]).
final class GeneratedFact<T> {
  GeneratedFact._(this._p, this._word);

  final IRawParticipant _p;
  final IFactWord<T> _word;

  /// Defines it as the participant's own; [readers] as a state's.
  IFactSayerOf<T> define({
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => FactSayerOf(
    _p.defineFact(
      FactDescriptor(
        _word.name,
        type: _word.shape.type,
        readers: readers,
        meta: meta,
      ),
      shape: _word.shape,
    ),
    _word.shape,
  );
}

/// A command as the generated owner base serves it and its client calls
/// it ([GeneratedWords.command]).
final class GeneratedCommand<P, R> {
  GeneratedCommand._(this._p, this._word);

  final IRawParticipant _p;
  final ICommandWord<P, R> _word;

  /// Defines it as the participant's own (SPEC §6.2), served by [handler]
  /// of its params (SPEC §23.4): what the handler does follows from the
  /// call. [callers], else the participant's default (`access.callers`);
  /// [whyNot] says why it cannot run now, or null. A word that only
  /// answers is a query ([IQueryWord]), not a command.
  IHandle serve(
    FutureOr<R> Function(P params) handler, {
    Callers? callers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    String? Function()? whyNot,
  }) => _p.defineCommand(
    CommandDescriptor(
      _word.name,
      params: _word.params.type,
      returns: _word.returns?.type,
      callers: _p.access.callersOf(_word.name, callers),
      deadline: deadline,
      meta: meta,
    ),
    _word.serve((c) => _served(_p, handler(c.params)), servedBy: _p.who),
    available: whyNot,
    params: _word.params,
    returns: _word.returns,
  );

  /// Calls it with [params] as the participant, under [id] when given (a
  /// retry with the same id runs once).
  Future<CallResult<R>> call(P params, {String? id}) async =>
      _word.answer(await _p.callAs(_word.name, params, _word.params, id: id));
}

/// A query as the generated owner base serves it and its client asks it
/// ([GeneratedWords.query]).
final class GeneratedQuery<P, R> {
  GeneratedQuery._(this._p, this._word);

  final IRawParticipant _p;
  final IQueryWord<P, R> _word;

  /// Defines it as the participant's own, answered by [handler] of its
  /// params (SPEC §23.4); [askers], else who may read its words
  /// (`access.readers`), else everyone. [whyNot] says why it cannot be
  /// asked now, or null.
  IHandle serve(
    FutureOr<R> Function(P params) handler, {
    Callers? askers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    String? Function()? whyNot,
  }) => _p.defineQuery(
    _word.describeWith(
      askers: _p.access.askersOf(askers),
      deadline: deadline,
      meta: meta,
    ),
    _word.serve((a) => _served(_p, handler(a.params))),
    available: whyNot,
    params: _word.params,
    returns: _word.returns,
  );

  /// Asks it as the participant; asking again asks again.
  Future<CallResult<R>> ask(P params) async =>
      _word.answer(await _p.callAs(_word.name, params, _word.params));
}
