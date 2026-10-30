// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'words.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [House].
enum HouseState<T> implements IStateWord<T> {
  light<bool>('house.light', Plain(BoolType()), key: 'room'),
  heat<num>('house.heat', Plain(NumType(min: 10, max: 28))),
  mode<Mode>('house.mode', EnumShape(Mode.values)),
  locked<bool>('house.locked', Plain(BoolType()));

  const HouseState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [House].
enum HouseCommand<P, R> implements ICommandWord<P, R> {
  setLight<HouseSetLight, void>(
    'house.set_light',
    RecordShape<HouseSetLight>(
      {'room': Part(Plain(ChoiceType('room'))), 'on': Part(Plain(BoolType()))},
      to: _$HouseSetLightTo,
      from: _$HouseSetLightFrom,
      get: _$HouseSetLightAt,
    ),
    null,
  ),
  setHeat<HouseSetHeat, void>(
    'house.set_heat',
    RecordShape<HouseSetHeat>(
      {'target': Part(Plain(NumType(min: 10, max: 28)))},
      to: _$HouseSetHeatTo,
      from: _$HouseSetHeatFrom,
      get: _$HouseSetHeatAt,
    ),
    null,
  ),
  setMode<HouseSetMode, void>(
    'house.set_mode',
    RecordShape<HouseSetMode>(
      {'mode': Part(EnumShape(Mode.values))},
      to: _$HouseSetModeTo,
      from: _$HouseSetModeFrom,
      get: _$HouseSetModeAt,
    ),
    null,
  ),
  lock<HouseLock, void>(
    'house.lock',
    RecordShape<HouseLock>(
      {'on': Part(Plain(BoolType()))},
      to: _$HouseLockTo,
      from: _$HouseLockFrom,
      get: _$HouseLockAt,
    ),
    null,
  );

  const HouseCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The queries of [House].
enum HouseQuery<P, R> implements IQueryWord<P, R> {
  rooms<HouseRooms, List<String>>(
    'house.rooms',
    RecordShape<HouseRooms>(
      {'lit': Part(Plain(BoolType()))},
      to: _$HouseRoomsTo,
      from: _$HouseRoomsFrom,
      get: _$HouseRoomsAt,
    ),
    ListShape(Plain(TextType())),
  );

  const HouseQuery(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R> returns;
}

/// The facts of [House].
enum HouseFact<T> implements IFactWord<T> {
  rang<HouseRang>(
    'house.rang',
    RecordShape<HouseRang>(
      {'who': Part(Plain(TextType()))},
      to: _$HouseRangTo,
      from: _$HouseRangFrom,
      get: _$HouseRangAt,
    ),
  ),
  motion<HouseMotion>(
    'house.motion',
    RecordShape<HouseMotion>(
      {'room': Part(Plain(TextType()))},
      to: _$HouseMotionTo,
      from: _$HouseMotionFrom,
      get: _$HouseMotionAt,
    ),
  );

  const HouseFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The kinds of choices [House] speaks of: what an owner gives by
/// `choices(HouseChoices.room, ...)`.
abstract final class HouseChoices {
  static const String room = 'room';
}

/// The owner base of [House]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class HouseOwnerBase implements IOwner {
  HouseOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: houseWords);
  }

  /// house.light, by room: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<bool> light = Keyed<bool>();

  /// house.heat: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<num> heat = Single<num>();

  /// house.mode: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<Mode> mode = Single<Mode>();

  /// house.locked: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<bool> locked = Single<bool>();

  IFactEmitterOf<HouseRang>? _$rang;
  IFactEmitterOf<HouseMotion>? _$motion;

  void _$say<T>(String fact, IFactEmitterOf<T>? e, T payload, Principal? by) {
    if (e == null) {
      IOwner.said(this, fact, payload);
    } else if (by == null) {
      e.emit(payload);
    } else {
      e.emitFor(payload, by);
    }
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Keyed.attach(light, p.state(HouseState.light).define());
    Single.attach(heat, p.state(HouseState.heat).define());
    Single.attach(mode, p.state(HouseState.mode).define());
    Single.attach(locked, p.state(HouseState.locked).define());
    _$rang = p.fact(HouseFact.rang).define();
    _$motion = p.fact(HouseFact.motion).define();
    p
        .command(HouseCommand.setLight)
        .serve(
          (x) => setLight(room: x.room, on: x.on),
          callers: Who.anyone,
        );
    p.command(HouseCommand.setHeat).serve((x) => setHeat(target: x.target));
    p.command(HouseCommand.setMode).serve((x) => setMode(mode: x.mode));
    p
        .command(HouseCommand.lock)
        .serve((x) => lock(on: x.on), whyNot: whyNotLock);
    p.query(HouseQuery.rooms).serve((x) => rooms(lit: x.lit));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Keyed.writeAll(light);
    Single.write(heat);
    Single.write(mode);
    Single.write(locked);
  }

  /// house.rang: said by `say`.
  late final HouseRangFact rang = HouseRangFact._(this);

  /// house.motion: said by `say`.
  late final HouseMotionFact motion = HouseMotionFact._(this);

  /// Serves house.set_light.
  void setLight({required String room, required bool on});

  /// Serves house.set_heat.
  void setHeat({required num target});

  /// Serves house.set_mode.
  void setMode({required Mode mode});

  /// Serves house.lock.
  void lock({required bool on});

  /// Why house.lock cannot run now; null when it can.
  String? whyNotLock();

  /// Answers house.rooms.
  List<String> rooms({required bool lit});
}

/// house.rang, as [HouseOwnerBase] says it.
final class HouseRangFact {
  HouseRangFact._(this._base);
  final HouseOwnerBase _base;

  /// Says house.rang; on behalf of [by], when given.
  void say({required String who, Principal? by}) =>
      _base._$say('house.rang', _base._$rang, (who: who), by);
}

/// house.motion, as [HouseOwnerBase] says it.
final class HouseMotionFact {
  HouseMotionFact._(this._base);
  final HouseOwnerBase _base;

  /// Says house.motion; on behalf of [by], when given.
  void say({required String room, Principal? by}) =>
      _base._$say('house.motion', _base._$motion, (room: room), by);
}

/// The words of [House] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [HouseClient] is them over a participant.
abstract interface class IHouseClient {
  /// house.light, by room: each value, and its changes.
  IKeyedOf<bool> get light;

  /// house.heat: its value now, and its changes.
  IStateOf<num> get heat;

  /// house.mode: its value now, and its changes.
  IStateOf<Mode> get mode;

  /// house.locked: its value now, and its changes.
  IStateOf<bool> get locked;

  /// Calls house.set_light; a call not done throws [CallNotDone].
  Future<void> setLight({required String room, required bool on});

  /// Calls house.set_heat; a call not done throws [CallNotDone].
  Future<void> setHeat({required num target});

  /// Calls house.set_mode; a call not done throws [CallNotDone].
  Future<void> setMode({required Mode mode});

  /// Calls house.lock; a call not done throws [CallNotDone].
  Future<void> lock({required bool on});

  /// Asks house.rooms; a call not done throws [CallNotDone].
  Future<List<String>> rooms({required bool lit});

  /// house.rang: what it says from now on, and its messages.
  IFactOf<HouseRang> get rang;

  /// house.motion: what it says from now on, and its messages.
  IFactOf<HouseMotion> get motion;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [House] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [House] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class HouseClient implements IHouseClient {
  HouseClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(houseWords.words, from: houseWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  HouseClient.of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(houseWords.words, from: houseWords.from);
  }

  final GeneratedWords _$words;

  @override
  IKeyedOf<bool> get light => _$words.keyedOf(HouseState.light);

  @override
  IStateOf<num> get heat => _$words.stateOf(HouseState.heat);

  @override
  IStateOf<Mode> get mode => _$words.stateOf(HouseState.mode);

  @override
  IStateOf<bool> get locked => _$words.stateOf(HouseState.locked);

  @override
  Future<void> setLight({required String room, required bool on}) async {
    final r = await _$words.command(HouseCommand.setLight).call((
      room: room,
      on: on,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> setHeat({required num target}) async {
    final r = await _$words.command(HouseCommand.setHeat).call((
      target: target,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> setMode({required Mode mode}) async {
    final r = await _$words.command(HouseCommand.setMode).call((mode: mode));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> lock({required bool on}) async {
    final r = await _$words.command(HouseCommand.lock).call((on: on));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<List<String>> rooms({required bool lit}) async {
    final r = await _$words.query(HouseQuery.rooms).ask((lit: lit));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  IFactOf<HouseRang> get rang => _$words.factOf(HouseFact.rang);

  @override
  IFactOf<HouseMotion> get motion => _$words.factOf(HouseFact.motion);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(houseWords.words);
}

/// The vocabulary of [House]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const houseWords = WordSet(
  'house',
  [
    ...HouseState.values,
    ...HouseCommand.values,
    ...HouseQuery.values,
    ...HouseFact.values,
  ],
  from: 'parlance',
  dartName: 'houseWords',
);

typedef HouseSetLight = ({String room, bool on});

Map<String, Object?> _$HouseSetLightTo(HouseSetLight p) => {
  'room': p.room,
  'on': p.on,
};

HouseSetLight _$HouseSetLightFrom(Map<String, Object?> m) =>
    (room: m['room']! as String, on: m['on']! as bool);

Object? _$HouseSetLightAt(HouseSetLight p, int i) => switch (i) {
  0 => p.room,
  _ => p.on,
};

typedef HouseSetHeat = ({num target});

Map<String, Object?> _$HouseSetHeatTo(HouseSetHeat p) => {'target': p.target};

HouseSetHeat _$HouseSetHeatFrom(Map<String, Object?> m) =>
    (target: m['target']! as num);

Object? _$HouseSetHeatAt(HouseSetHeat p, int i) => p.target;

typedef HouseSetMode = ({Mode mode});

Map<String, Object?> _$HouseSetModeTo(HouseSetMode p) => {'mode': p.mode};

HouseSetMode _$HouseSetModeFrom(Map<String, Object?> m) =>
    (mode: m['mode']! as Mode);

Object? _$HouseSetModeAt(HouseSetMode p, int i) => p.mode;

typedef HouseLock = ({bool on});

Map<String, Object?> _$HouseLockTo(HouseLock p) => {'on': p.on};

HouseLock _$HouseLockFrom(Map<String, Object?> m) => (on: m['on']! as bool);

Object? _$HouseLockAt(HouseLock p, int i) => p.on;

typedef HouseRooms = ({bool lit});

Map<String, Object?> _$HouseRoomsTo(HouseRooms p) => {'lit': p.lit};

HouseRooms _$HouseRoomsFrom(Map<String, Object?> m) => (lit: m['lit']! as bool);

Object? _$HouseRoomsAt(HouseRooms p, int i) => p.lit;

typedef HouseRang = ({String who});

Map<String, Object?> _$HouseRangTo(HouseRang p) => {'who': p.who};

HouseRang _$HouseRangFrom(Map<String, Object?> m) => (who: m['who']! as String);

Object? _$HouseRangAt(HouseRang p, int i) => p.who;

typedef HouseMotion = ({String room});

Map<String, Object?> _$HouseMotionTo(HouseMotion p) => {'room': p.room};

HouseMotion _$HouseMotionFrom(Map<String, Object?> m) =>
    (room: m['room']! as String);

Object? _$HouseMotionAt(HouseMotion p, int i) => p.room;

/// The states of [Visit].
enum VisitState<T> implements IStateWord<T> {
  guests<List<String>>('visit.guests', ListShape(Plain(TextType())));

  const VisitState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Visit].
enum VisitCommand<P, R> implements ICommandWord<P, R> {
  leave<VisitLeave, void>(
    'visit.leave',
    RecordShape<VisitLeave>(
      {'who': Part(Plain(TextType()))},
      to: _$VisitLeaveTo,
      from: _$VisitLeaveFrom,
      get: _$VisitLeaveAt,
    ),
    null,
  );

  const VisitCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The owner base of [Visit]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class VisitOwnerBase implements IOwner {
  VisitOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: visitWords);
  }

  /// visit.guests: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<List<String>> guests = Single<List<String>>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Single.attach(guests, p.state(VisitState.guests).define());
    p.command(VisitCommand.leave).serve((x) => leave(who: x.who));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(guests);
  }

  /// Serves visit.leave.
  void leave({required String who});
}

/// The words of [Visit] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [VisitClient] is them over a participant.
abstract interface class IVisitClient {
  /// visit.guests: its value now, and its changes.
  IStateOf<List<String>> get guests;

  /// Calls visit.leave; a call not done throws [CallNotDone].
  Future<void> leave({required String who});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Visit] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Visit] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class VisitClient implements IVisitClient {
  VisitClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(visitWords.words, from: visitWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  VisitClient.of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(visitWords.words, from: visitWords.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<List<String>> get guests => _$words.stateOf(VisitState.guests);

  @override
  Future<void> leave({required String who}) async {
    final r = await _$words.command(VisitCommand.leave).call((who: who));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(visitWords.words);
}

/// The vocabulary of [Visit]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const visitWords = WordSet(
  'visit',
  [...VisitState.values, ...VisitCommand.values],
  from: 'parlance',
  dartName: 'visitWords',
);

typedef VisitLeave = ({String who});

Map<String, Object?> _$VisitLeaveTo(VisitLeave p) => {'who': p.who};

VisitLeave _$VisitLeaveFrom(Map<String, Object?> m) =>
    (who: m['who']! as String);

Object? _$VisitLeaveAt(VisitLeave p, int i) => p.who;
