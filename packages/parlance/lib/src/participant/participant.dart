import 'dart:async';

import 'package:clock/clock.dart' show Clock;

import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/words.dart';
import '../view/view.dart';

/// What a participant may do beyond defining words in its namespaces
/// (SPEC §22.2). Each check answers why not, or null to allow.
final class ParticipantRights {
  const ParticipantRights({this.define, this.produce, this.speakFor});

  /// Define [d], a word in its namespaces: a further check (callers that
  /// name outsiders, a kind of word). Null: every word in its namespaces.
  final String? Function(Principal who, Descriptor d)? define;

  /// Say [fact], an open fact another defined. Null: none.
  final String? Function(Principal who, String fact)? produce;

  /// Say [fact] on behalf of [by]: its cause is theirs, and so are the
  /// rights of what follows from it. Null: no one.
  final String? Function(Principal who, Principal by, String fact)? speakFor;

  /// Defines in its namespaces, and nothing more.
  static const none = ParticipantRights();
}

/// A part of the app as it speaks (SPEC §22): it sees the registry only
/// through this, as one principal, [who]. It reads, watches, hears and
/// calls what [who] may; it defines words only in its [namespaces], and
/// writes and says them as [who]. The same whether the registry is in this
/// process ([LocalParticipant]) or across a connection.
///
/// `main` makes one per part and hands it over; the part never gets the
/// registry itself, so what its words' callers and readers say holds for
/// it.
abstract interface class IParticipant implements IRegistryView, IHandle {
  /// Who it speaks as.
  Principal get who;

  /// The first words of the names it may define: `orders` for
  /// `orders.cancel` and `orders.list.page`.
  Set<String> get namespaces;

  ParticipantRights get rights;

  /// Where it reads the time: the registry's clock in this process.
  Clock get clock;

  /// The value of [state] (of [key]) now, then on every change; null
  /// alone when [who] may not read it.
  Stream<Object?> watch(String state, {String? key});

  /// Calls [command] as [who]. A handler's nested call passes [cause]
  /// (`call.causeFor(who)`), so it follows from the call being served.
  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
  });

  /// Defines a state of its own, with [who] its only writer.
  IStateHandle defineState(StateDescriptor d);

  /// Defines a command of its own, served by [handler].
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
  });

  /// Defines a fact of its own, with [who] its producer.
  IFactHandle defineFact(FactDescriptor d);

  /// Another producer of an open [fact], as far as [rights] let it.
  IFactHandle producer(String fact);

  /// A guard (SPEC §10) on calls of its own commands only: what it judges
  /// is its own, never another's command.
  IHandle addGuard(String id, GuardCheck check, {bool overridable = true});

  /// Registers a kind of entities it keeps (SPEC §3).
  IHandle registerKind(EntityKind kind);

  /// The entities of [kind], one it registered, changed.
  void entitiesChanged(String kind);

  /// Runs [writes], its writes and facts committed as one tick.
  void batch(void Function() writes);

  /// Withdraws everything it defined, registered and added.
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

  /// Every value, by key.
  Map<String?, T> readAll() => {
    for (final e in participant.readAll(word.name).entries)
      if (e.value != null) e.key: word.shape.fromJson(e.value),
  };

  /// Its value now, then on every change.
  Stream<T?> watch({String? key}) =>
      participant.watch(word.name, key: key).map(word.decode);

  WordStatus get status => participant.status(word.name);
  Stream<WordStatus> get statusChanges => participant.statusChanges(word.name);
}

/// A command as a participant has it, typed.
final class ParticipantCommandOf<P, R> {
  ParticipantCommandOf._(this.participant, this.word);

  final IParticipant participant;
  final ICommandWord<P, R> word;

  /// Defines it as the participant's own, served by [handler] (SPEC §6.2).
  IHandle define(
    FutureOr<R> Function(CommandCallOf<P> call) handler, {
    required Callers callers,
    Sets? sets,
    bool interceptable = false,
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
        callers: callers,
        sets: sets,
        interceptable: interceptable,
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

  /// Calls it with [params] as the participant.
  Future<CallResult<R>> call(P params, {String? id, Cause? cause}) async =>
      word.answer(
        await participant.call(
          word.name,
          word.params.toJson(params),
          id: id,
          cause: cause,
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

  /// The last [count] the registry keeps, oldest first.
  Future<List<Fact<T>>> recent(int count) async => [
    for (final m in await participant.recent(word.name, count)) _decode(m),
  ];

  WordStatus get status => participant.status(word.name);
  Stream<WordStatus> get statusChanges => participant.statusChanges(word.name);
}
