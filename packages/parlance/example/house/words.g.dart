// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'words.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [House].
enum HouseState<T> implements IStateWord<T> {
  light<bool>('house.light.on', Plain(BoolType()), key: 'room'),
  heat<num>('house.heat.target', Plain(NumType(min: 10, max: 28))),
  mode<Mode>('house.mode', EnumShape(Mode.values)),
  locked<bool>('house.door.locked', Plain(BoolType()));

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
    'house.light.set',
    RecordShape<HouseSetLight>(
      {'room': Part(Plain(ChoiceType('room'))), 'on': Part(Plain(BoolType()))},
      to: _$HouseSetLightTo,
      from: _$HouseSetLightFrom,
      get: _$HouseSetLightAt,
    ),
    null,
  ),
  setHeat<HouseSetHeat, void>(
    'house.heat.set',
    RecordShape<HouseSetHeat>(
      {'target': Part(Plain(NumType(min: 10, max: 28)))},
      to: _$HouseSetHeatTo,
      from: _$HouseSetHeatFrom,
      get: _$HouseSetHeatAt,
    ),
    null,
  ),
  setMode<HouseSetMode, void>(
    'house.mode.set',
    RecordShape<HouseSetMode>(
      {'mode': Part(EnumShape(Mode.values))},
      to: _$HouseSetModeTo,
      from: _$HouseSetModeFrom,
      get: _$HouseSetModeAt,
    ),
    null,
  ),
  lock<HouseLock, void>(
    'house.door.lock',
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
    'house.doorbell.rang',
    RecordShape<HouseRang>(
      {'who': Part(Plain(TextType()))},
      to: _$HouseRangTo,
      from: _$HouseRangFrom,
      get: _$HouseRangAt,
    ),
  ),
  motion<HouseMotion>(
    'house.motion.seen',
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
    IOwner.made(this, define: _$define, write: _$write);
  }

  /// house.light.on, by room: what this owner set of each,
  /// read and written as a map is.
  final Keyed<bool> light = Keyed<bool>();

  IStateWriterOf<num>? _$heat;
  num? _$heatNow;
  var _$heatSet = false;

  /// house.heat.target, as this owner last set it.
  num? get heat => _$heatNow;

  /// Sets house.heat.target; null removes it.
  set heat(num? value) {
    _$heatNow = value;
    _$heatSet = true;
    value == null ? _$heat?.remove() : _$heat?.set(value);
  }

  IStateWriterOf<Mode>? _$mode;
  Mode? _$modeNow;
  var _$modeSet = false;

  /// house.mode, as this owner last set it.
  Mode? get mode => _$modeNow;

  /// Sets house.mode; null removes it.
  set mode(Mode? value) {
    _$modeNow = value;
    _$modeSet = true;
    value == null ? _$mode?.remove() : _$mode?.set(value);
  }

  IStateWriterOf<bool>? _$locked;
  bool? _$lockedNow;
  var _$lockedSet = false;

  /// house.door.locked, as this owner last set it.
  bool? get locked => _$lockedNow;

  /// Sets house.door.locked; null removes it.
  set locked(bool? value) {
    _$lockedNow = value;
    _$lockedSet = true;
    value == null ? _$locked?.remove() : _$locked?.set(value);
  }

  IFactEmitterOf<HouseRang>? _$rang;
  IFactEmitterOf<HouseMotion>? _$motion;

  /// What it said while not attached, for a test to read:
  /// each fact's name and payload, in order.
  final List<(String, Object?)> said = [];

  void _$say<T>(String fact, IFactEmitterOf<T>? e, T payload, Principal? by) {
    if (e == null) {
      said.add((fact, payload));
    } else if (by == null) {
      e.emit(payload);
    } else {
      e.emitFor(payload, by);
    }
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords.of(participant);
    Keyed.attach(light, p.state(HouseState.light).define());
    _$heat = p.state(HouseState.heat).define();
    _$mode = p.state(HouseState.mode).define();
    _$locked = p.state(HouseState.locked).define();
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
        .serve((x) => lock(on: x.on), available: whyNotLock);
    p.query(HouseQuery.rooms).serve((x) => rooms(lit: x.lit));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Keyed.writeAll(light);
    if (_$heatSet) {
      final v = _$heatNow;
      v == null ? _$heat!.remove() : _$heat!.set(v);
    }
    if (_$modeSet) {
      final v = _$modeNow;
      v == null ? _$mode!.remove() : _$mode!.set(v);
    }
    if (_$lockedSet) {
      final v = _$lockedNow;
      v == null ? _$locked!.remove() : _$locked!.set(v);
    }
  }

  /// Says house.doorbell.rang; on behalf of [by], when given.
  void rang({required String who, Principal? by}) =>
      _$say('house.doorbell.rang', _$rang, (who: who), by);

  /// Says house.motion.seen; on behalf of [by], when given.
  void motion({required String room, Principal? by}) =>
      _$say('house.motion.seen', _$motion, (room: room), by);

  /// Serves house.light.set.
  void setLight({required String room, required bool on});

  /// Serves house.heat.set.
  void setHeat({required num target});

  /// Serves house.mode.set.
  void setMode({required Mode mode});

  /// Serves house.door.lock.
  void lock({required bool on});

  /// Why house.door.lock cannot run now; null when it can.
  String? whyNotLock();

  /// Answers house.rooms.
  List<String> rooms({required bool lit});
}

/// The words of [House] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [HouseClient] is them over a participant.
abstract interface class IHouseClient {
  /// house.light.on of [room] now.
  bool? lightOf(String room);

  /// house.light.on of every room, by key.
  Map<String, bool> get lightAll;

  /// house.light.on of [room] now, then on every change.
  Stream<bool?> lightChanges(String room);

  /// house.heat.target now.
  num? get heat;

  /// house.heat.target now, then whenever it changes.
  Stream<num?> get heatChanges;

  /// house.mode now.
  Mode? get mode;

  /// house.mode now, then whenever it changes.
  Stream<Mode?> get modeChanges;

  /// house.door.locked now.
  bool? get locked;

  /// house.door.locked now, then whenever it changes.
  Stream<bool?> get lockedChanges;

  /// Calls house.light.set; a call not done throws [CallNotDone].
  Future<void> setLight({required String room, required bool on});

  /// Calls house.heat.set; a call not done throws [CallNotDone].
  Future<void> setHeat({required num target});

  /// Calls house.mode.set; a call not done throws [CallNotDone].
  Future<void> setMode({required Mode mode});

  /// Calls house.door.lock; a call not done throws [CallNotDone].
  Future<void> lock({required bool on});

  /// Asks house.rooms; a call not done throws [CallNotDone].
  Future<List<String>> rooms({required bool lit});

  /// house.doorbell.rang, as it is said from now on: what it says.
  Stream<({String who})> get rang;

  /// house.motion.seen, as it is said from now on: what it says.
  Stream<({String room})> get motion;
}

/// The words of [House] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class HouseClient implements IHouseClient {
  HouseClient(IParticipant participant)
    : _$words = GeneratedWords.of(participant) {
    _$words.builtAgainst(houseWords.words, from: houseWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  HouseClient.of(IOwner owner) : _$words = GeneratedWords.ofOwner(owner) {
    _$words.builtAgainst(houseWords.words, from: houseWords.from);
  }

  final GeneratedWords _$words;

  @override
  bool? lightOf(String room) => _$words.state(HouseState.light).read(key: room);

  @override
  Map<String, bool> get lightAll => {
    for (final MapEntry(:key, :value)
        in _$words.state(HouseState.light).readAll().entries)
      ?key: value,
  };

  @override
  Stream<bool?> lightChanges(String room) =>
      _$words.later(() => _$words.state(HouseState.light).watch(key: room));

  @override
  num? get heat => _$words.state(HouseState.heat).read();

  @override
  Stream<num?> get heatChanges =>
      _$words.later(() => _$words.state(HouseState.heat).watch());

  @override
  Mode? get mode => _$words.state(HouseState.mode).read();

  @override
  Stream<Mode?> get modeChanges =>
      _$words.later(() => _$words.state(HouseState.mode).watch());

  @override
  bool? get locked => _$words.state(HouseState.locked).read();

  @override
  Stream<bool?> get lockedChanges =>
      _$words.later(() => _$words.state(HouseState.locked).watch());

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
  Stream<({String who})> get rang => _$words.later(
    () => _$words.fact(HouseFact.rang).stream.map((f) => f.payload),
  );

  @override
  Stream<({String room})> get motion => _$words.later(
    () => _$words.fact(HouseFact.motion).stream.map((f) => f.payload),
  );

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word) => _$words.status(word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  /// Each word of [House] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(houseWords.words);

  /// house.doorbell.rang, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<HouseRang>> get rangFacts =>
      _$words.later(() => _$words.fact(HouseFact.rang).stream);

  /// house.motion.seen, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<HouseMotion>> get motionFacts =>
      _$words.later(() => _$words.fact(HouseFact.motion).stream);
}

/// The vocabulary of [House]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const houseWords = WordSet('house', [
  ...HouseState.values,
  ...HouseCommand.values,
  ...HouseQuery.values,
  ...HouseFact.values,
], from: 'parlance');

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
    IOwner.made(this, define: _$define, write: _$write);
  }

  IStateWriterOf<List<String>>? _$guests;
  List<String>? _$guestsNow;
  var _$guestsSet = false;

  /// visit.guests, as this owner last set it.
  List<String>? get guests => _$guestsNow;

  /// Sets visit.guests; null removes it.
  set guests(List<String>? value) {
    _$guestsNow = value;
    _$guestsSet = true;
    value == null ? _$guests?.remove() : _$guests?.set(value);
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords.of(participant);
    _$guests = p.state(VisitState.guests).define();
    p.command(VisitCommand.leave).serve((x) => leave(who: x.who));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    if (_$guestsSet) {
      final v = _$guestsNow;
      v == null ? _$guests!.remove() : _$guests!.set(v);
    }
  }

  /// Serves visit.leave.
  void leave({required String who});
}

/// The words of [Visit] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [VisitClient] is them over a participant.
abstract interface class IVisitClient {
  /// visit.guests now.
  List<String>? get guests;

  /// visit.guests now, then whenever it changes.
  Stream<List<String>?> get guestsChanges;

  /// Calls visit.leave; a call not done throws [CallNotDone].
  Future<void> leave({required String who});
}

/// The words of [Visit] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class VisitClient implements IVisitClient {
  VisitClient(IParticipant participant)
    : _$words = GeneratedWords.of(participant) {
    _$words.builtAgainst(visitWords.words, from: visitWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  VisitClient.of(IOwner owner) : _$words = GeneratedWords.ofOwner(owner) {
    _$words.builtAgainst(visitWords.words, from: visitWords.from);
  }

  final GeneratedWords _$words;

  @override
  List<String>? get guests => _$words.state(VisitState.guests).read();

  @override
  Stream<List<String>?> get guestsChanges =>
      _$words.later(() => _$words.state(VisitState.guests).watch());

  @override
  Future<void> leave({required String who}) async {
    final r = await _$words.command(VisitCommand.leave).call((who: who));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word) => _$words.status(word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  /// Each word of [Visit] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(visitWords.words);
}

/// The vocabulary of [Visit]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const visitWords = WordSet('visit', [
  ...VisitState.values,
  ...VisitCommand.values,
], from: 'parlance');

typedef VisitLeave = ({String who});

Map<String, Object?> _$VisitLeaveTo(VisitLeave p) => {'who': p.who};

VisitLeave _$VisitLeaveFrom(Map<String, Object?> m) =>
    (who: m['who']! as String);

Object? _$VisitLeaveAt(VisitLeave p, int i) => p.who;
