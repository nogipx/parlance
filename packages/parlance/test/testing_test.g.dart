// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'testing_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Weather].
enum WeatherState<T> implements IStateWord<T> {
  outside<num>('weather.outside', PlainShape(NumType()));

  const WeatherState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The owner base of [Weather]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class WeatherOwnerBase implements IOwner {
  WeatherOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: WeatherVocabulary.definition,
    );
  }

  /// weather.outside: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<num> outside = Single<num>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(outside, p.state(WeatherState.outside).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(outside);
  }
}

/// The words of [Weather] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IWeatherClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IWeatherClient({
    required IParticipant participant,
    required Principal target,
  }) = _$WeatherClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IWeatherClient.of({
    required IOwner owner,
    required Principal target,
  }) = _$WeatherClient._of;

  /// weather.outside: its value now, and its changes.
  IStateOf<num> get outside;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Weather] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Weather] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$WeatherClient implements IWeatherClient {
  _$WeatherClient({
    required IParticipant participant,
    required Principal target,
  }) : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      WeatherVocabulary.words,
      from: WeatherVocabulary.definition.from,
    );
  }

  _$WeatherClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      WeatherVocabulary.words,
      from: WeatherVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IStateOf<num> get outside => _$words.stateOf(WeatherState.outside);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(WeatherVocabulary.words);
}

/// The vocabulary of [Weather], independent of its publishing target.
abstract final class WeatherVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'weather';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...WeatherState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'WeatherVocabulary.definition',
  );
}

/// The commands of [Heater].
enum HeaterCommand<P, R> implements ICommandWord<P, R> {
  setPower<HeaterSetPower, void>(
    'heater.set_power',
    RecordShape<HeaterSetPower>(
      {'on': Part(PlainShape(BoolType()))},
      to: _$HeaterSetPowerTo,
      from: _$HeaterSetPowerFrom,
      get: _$HeaterSetPowerAt,
    ),
    null,
  );

  const HeaterCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The owner base of [Heater]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class HeaterOwnerBase implements IOwner {
  HeaterOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: HeaterVocabulary.definition,
    );
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    p.command(HeaterCommand.setPower).serve((x) => setPower(on: x.on));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }

  /// Serves heater.set_power.
  void setPower({required bool on});
}

/// The words of [Heater] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IHeaterClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IHeaterClient({
    required IParticipant participant,
    required Principal target,
  }) = _$HeaterClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IHeaterClient.of({required IOwner owner, required Principal target}) =
      _$HeaterClient._of;

  /// Calls heater.set_power; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> setPower({required bool on, CancellationToken? cancel});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Heater] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Heater] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$HeaterClient implements IHeaterClient {
  _$HeaterClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      HeaterVocabulary.words,
      from: HeaterVocabulary.definition.from,
    );
  }

  _$HeaterClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      HeaterVocabulary.words,
      from: HeaterVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  Future<void> setPower({required bool on, CancellationToken? cancel}) async {
    final r = await _$words.command(HeaterCommand.setPower).call((
      on: on,
    ), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(HeaterVocabulary.words);
}

/// The vocabulary of [Heater], independent of its publishing target.
abstract final class HeaterVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'heater';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...HeaterCommand.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'HeaterVocabulary.definition',
  );
}

typedef HeaterSetPower = ({bool on});

Map<String, Object?> _$HeaterSetPowerTo(HeaterSetPower p) => {'on': p.on};

HeaterSetPower _$HeaterSetPowerFrom(Map<String, Object?> m) =>
    (on: m['on']! as bool);

Object? _$HeaterSetPowerAt(HeaterSetPower p, int i) => p.on;

/// The states of [Thermostat].
enum ThermostatState<T> implements IStateWord<T> {
  heating<bool>('thermostat.heating', PlainShape(BoolType()));

  const ThermostatState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The facts of [Thermostat].
enum ThermostatFact<T> implements IFactWord<T> {
  adjusted<ThermostatAdjusted>(
    'thermostat.adjusted',
    RecordShape<ThermostatAdjusted>(
      {'on': Part(PlainShape(BoolType()))},
      to: _$ThermostatAdjustedTo,
      from: _$ThermostatAdjustedFrom,
      get: _$ThermostatAdjustedAt,
    ),
  );

  const ThermostatFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The owner base of [Thermostat]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class ThermostatOwnerBase implements IOwner {
  ThermostatOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: ThermostatVocabulary.definition,
    );
  }

  /// thermostat.heating: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<bool> heating = Single<bool>();

  IFactSayerOf<ThermostatAdjusted>? _$adjusted;

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(heating, p.state(ThermostatState.heating).define());
    _$adjusted = p.fact(ThermostatFact.adjusted).define();
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(heating);
  }

  /// thermostat.adjusted: said by `say`.
  late final ThermostatAdjustedFact adjusted = ThermostatAdjustedFact._(this);
}

/// thermostat.adjusted, as [ThermostatOwnerBase] says it.
final class ThermostatAdjustedFact {
  ThermostatAdjustedFact._(this._base);
  final ThermostatOwnerBase _base;

  /// Says thermostat.adjusted; on behalf of [by], when given.
  /// Said while its owner is not attached, no one hears it.
  void say({required bool on, Principal? by}) =>
      _base._$adjusted?.say((on: on), by: by);
}

/// The words of [Thermostat] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IThermostatClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IThermostatClient({
    required IParticipant participant,
    required Principal target,
  }) = _$ThermostatClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IThermostatClient.of({
    required IOwner owner,
    required Principal target,
  }) = _$ThermostatClient._of;

  /// thermostat.heating: its value now, and its changes.
  IStateOf<bool> get heating;

  /// thermostat.adjusted: what it says from now on, and its messages.
  IFactOf<ThermostatAdjusted> get adjusted;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Thermostat] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Thermostat] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$ThermostatClient implements IThermostatClient {
  _$ThermostatClient({
    required IParticipant participant,
    required Principal target,
  }) : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      ThermostatVocabulary.words,
      from: ThermostatVocabulary.definition.from,
    );
  }

  _$ThermostatClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      ThermostatVocabulary.words,
      from: ThermostatVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IStateOf<bool> get heating => _$words.stateOf(ThermostatState.heating);

  @override
  IFactOf<ThermostatAdjusted> get adjusted =>
      _$words.factOf(ThermostatFact.adjusted);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(ThermostatVocabulary.words);
}

/// The vocabulary of [Thermostat], independent of its publishing target.
abstract final class ThermostatVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'thermostat';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [
    ...ThermostatState.values,
    ...ThermostatFact.values,
  ];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'ThermostatVocabulary.definition',
  );
}

typedef ThermostatAdjusted = ({bool on});

Map<String, Object?> _$ThermostatAdjustedTo(ThermostatAdjusted p) => {
  'on': p.on,
};

ThermostatAdjusted _$ThermostatAdjustedFrom(Map<String, Object?> m) =>
    (on: m['on']! as bool);

Object? _$ThermostatAdjustedAt(ThermostatAdjusted p, int i) => p.on;

/// The states of [Lamp].
enum LampState<T> implements IStateWord<T> {
  on<bool>('lamp.on', PlainShape(BoolType()), key: 'room');

  const LampState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The owner base of [Lamp]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class LampOwnerBase implements IOwner {
  LampOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: LampVocabulary.definition,
    );
  }

  /// lamp.on, by room: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<bool> on = Keyed<bool>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Keyed.attach(on, p.state(LampState.on).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Keyed.writeAll(on);
  }
}

/// The words of [Lamp] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class ILampClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory ILampClient({
    required IParticipant participant,
    required Principal target,
  }) = _$LampClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ILampClient.of({required IOwner owner, required Principal target}) =
      _$LampClient._of;

  /// lamp.on, by room: each value, and its changes.
  IKeyedOf<bool> get on;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Lamp] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Lamp] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$LampClient implements ILampClient {
  _$LampClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      LampVocabulary.words,
      from: LampVocabulary.definition.from,
    );
  }

  _$LampClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      LampVocabulary.words,
      from: LampVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IKeyedOf<bool> get on => _$words.keyedOf(LampState.on);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(LampVocabulary.words);
}

/// The vocabulary of [Lamp], independent of its publishing target.
abstract final class LampVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'lamp';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...LampState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'LampVocabulary.definition',
  );
}
