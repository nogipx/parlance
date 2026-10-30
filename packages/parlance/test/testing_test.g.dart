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
      vocabulary: weatherWords,
    );
  }

  /// weather.outside: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<num> outside = Single<num>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
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
  factory IWeatherClient(IParticipant participant) = _$WeatherClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IWeatherClient.of(IOwner owner) = _$WeatherClient._of;

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
  _$WeatherClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(weatherWords.words, from: weatherWords.from);
  }

  _$WeatherClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(weatherWords.words, from: weatherWords.from);
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
      _$words.mismatches(weatherWords.words);
}

/// The vocabulary of [Weather]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const weatherWords = WordSet(
  'weather',
  [...WeatherState.values],
  from: 'parlance',
  dartName: 'weatherWords',
);

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
      vocabulary: heaterWords,
    );
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
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
  factory IHeaterClient(IParticipant participant) = _$HeaterClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IHeaterClient.of(IOwner owner) = _$HeaterClient._of;

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
  _$HeaterClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(heaterWords.words, from: heaterWords.from);
  }

  _$HeaterClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(heaterWords.words, from: heaterWords.from);
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
      _$words.mismatches(heaterWords.words);
}

/// The vocabulary of [Heater]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const heaterWords = WordSet(
  'heater',
  [...HeaterCommand.values],
  from: 'parlance',
  dartName: 'heaterWords',
);

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
      vocabulary: thermostatWords,
    );
  }

  /// thermostat.heating: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<bool> heating = Single<bool>();

  IFactSayerOf<ThermostatAdjusted>? _$adjusted;

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
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
  factory IThermostatClient(IParticipant participant) = _$ThermostatClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IThermostatClient.of(IOwner owner) = _$ThermostatClient._of;

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
  _$ThermostatClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(thermostatWords.words, from: thermostatWords.from);
  }

  _$ThermostatClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(thermostatWords.words, from: thermostatWords.from);
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
      _$words.mismatches(thermostatWords.words);
}

/// The vocabulary of [Thermostat]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const thermostatWords = WordSet(
  'thermostat',
  [...ThermostatState.values, ...ThermostatFact.values],
  from: 'parlance',
  dartName: 'thermostatWords',
);

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

/// The kinds of choices [Lamp] speaks of: what an owner gives by
/// `choices(LampChoices.room, ...)`.
abstract final class LampChoices {
  static const String room = 'room';
}

/// The owner base of [Lamp]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class LampOwnerBase implements IOwner {
  LampOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: lampWords);
  }

  /// lamp.on, by room: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<bool> on = Keyed<bool>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
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
  factory ILampClient(IParticipant participant) = _$LampClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ILampClient.of(IOwner owner) = _$LampClient._of;

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
  _$LampClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(lampWords.words, from: lampWords.from);
  }

  _$LampClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(lampWords.words, from: lampWords.from);
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
      _$words.mismatches(lampWords.words);
}

/// The vocabulary of [Lamp]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const lampWords = WordSet(
  'lamp',
  [...LampState.values],
  from: 'parlance',
  dartName: 'lampWords',
);
