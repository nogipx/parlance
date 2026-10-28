// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'words.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [House].
enum HouseState<T> implements IStateWord<T> {
  light<bool>('house.light.on', Plain(BoolType()), key: room),
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
      {'room': Part(Plain(RefType(room))), 'on': Part(Plain(BoolType()))},
      to: _$HouseSetLightTo,
      from: _$HouseSetLightFrom,
    ),
    null,
  ),
  setHeat<HouseSetHeat, void>(
    'house.heat.set',
    RecordShape<HouseSetHeat>(
      {'target': Part(Plain(NumType(min: 10, max: 28)))},
      to: _$HouseSetHeatTo,
      from: _$HouseSetHeatFrom,
    ),
    null,
  ),
  setMode<HouseSetMode, void>(
    'house.mode.set',
    RecordShape<HouseSetMode>(
      {'mode': Part(EnumShape(Mode.values))},
      to: _$HouseSetModeTo,
      from: _$HouseSetModeFrom,
    ),
    null,
  ),
  lock<HouseLock, void>(
    'house.door.lock',
    RecordShape<HouseLock>(
      {'on': Part(Plain(BoolType()))},
      to: _$HouseLockTo,
      from: _$HouseLockFrom,
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
    ),
  ),
  motion<HouseMotion>(
    'house.motion.seen',
    RecordShape<HouseMotion>(
      {'room': Part(Plain(TextType()))},
      to: _$HouseMotionTo,
      from: _$HouseMotionFrom,
    ),
  );

  const HouseFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The owner base of [House]: it defines every word, keeps a
/// writer of each state, says each fact by a method of its
/// params, and serves each command and query by a handler to
/// write (`call.inReply`: the cause of what it does in reply).
abstract base class HouseOwner extends Owner {
  /// Writes house.light.on.
  late final StateWriterOf<bool> light;

  /// Writes house.heat.target.
  late final StateWriterOf<num> heat;

  /// Writes house.mode.
  late final StateWriterOf<Mode> mode;

  /// Writes house.door.locked.
  late final StateWriterOf<bool> locked;
  late final FactEmitterOf<HouseRang> _rang;
  late final FactEmitterOf<HouseMotion> _motion;

  @override
  void define(IParticipant p) {
    light = keep(p.state(HouseState.light).define());
    heat = keep(p.state(HouseState.heat).define());
    mode = keep(p.state(HouseState.mode).define());
    locked = keep(p.state(HouseState.locked).define());
    _rang = keep(p.fact(HouseFact.rang).define());
    _motion = keep(p.fact(HouseFact.motion).define());
    keep(
      p.command(HouseCommand.setLight).define(setLight, callers: Who.anyone),
    );
    keep(p.command(HouseCommand.setHeat).define(setHeat));
    keep(p.command(HouseCommand.setMode).define(setMode));
    keep(p.command(HouseCommand.lock).define(lock, available: whyNotLock));
    keep(p.query(HouseQuery.rooms).define(rooms));
    defineMore(p);
  }

  /// Says house.doorbell.rang; [cause] as a write's.
  void rang({required String who, Cause? cause}) =>
      _rang.emit((who: who), cause: cause);

  /// Says house.motion.seen; [cause] as a write's.
  void motion({required String room, Cause? cause}) =>
      _motion.emit((room: room), cause: cause);

  /// What [House] does not say: kinds, guards, words named at
  /// run time. After its words are defined.
  void defineMore(IParticipant p) {}

  /// Serves house.light.set.
  void setLight(CommandCallOf<HouseSetLight> call);

  /// Serves house.heat.set.
  void setHeat(CommandCallOf<HouseSetHeat> call);

  /// Serves house.mode.set.
  void setMode(CommandCallOf<HouseSetMode> call);

  /// Serves house.door.lock.
  void lock(CommandCallOf<HouseLock> call);

  /// Why house.door.lock cannot run now; null when it can.
  String? whyNotLock();

  /// Answers house.rooms.
  List<String> rooms(QueryAsk<HouseRooms> ask);
}

/// The words of [House] as a consumer uses them, through a
/// view: its participant, a `LocalView`, a `MirrorView`.
final class HouseClient {
  const HouseClient(this.view);

  final IRegistryView view;

  /// Whether [word] is there for the view now (SPEC §6.5).
  WordStatus status(IWord word) => view.status(word.name);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => view.statusChanges(word.name);

  /// house.light.on of [room] now.
  bool? lightOf(String room) => view.state(HouseState.light).read(key: room);

  /// house.light.on of every room, by key.
  Map<String?, bool> get lightAll => view.state(HouseState.light).readAll();

  /// house.light.on of [room] now, then on every change.
  Stream<bool?> lightChanges(String room) =>
      view.state(HouseState.light).watch(key: room);

  /// house.heat.target now.
  num? get heat => view.state(HouseState.heat).read();

  /// house.heat.target now, then whenever it changes.
  Stream<num?> get heatChanges => view.state(HouseState.heat).watch();

  /// house.mode now.
  Mode? get mode => view.state(HouseState.mode).read();

  /// house.mode now, then whenever it changes.
  Stream<Mode?> get modeChanges => view.state(HouseState.mode).watch();

  /// house.door.locked now.
  bool? get locked => view.state(HouseState.locked).read();

  /// house.door.locked now, then whenever it changes.
  Stream<bool?> get lockedChanges => view.state(HouseState.locked).watch();

  /// Calls house.light.set; a call not done throws [CallNotDone].
  Future<void> setLight({required String room, required bool on}) async {
    final r = await view.command(HouseCommand.setLight).call((
      room: room,
      on: on,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  /// Calls house.heat.set; a call not done throws [CallNotDone].
  Future<void> setHeat({required num target}) async {
    final r = await view.command(HouseCommand.setHeat).call((target: target));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  /// Calls house.mode.set; a call not done throws [CallNotDone].
  Future<void> setMode({required Mode mode}) async {
    final r = await view.command(HouseCommand.setMode).call((mode: mode));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  /// Calls house.door.lock; a call not done throws [CallNotDone].
  Future<void> lock({required bool on}) async {
    final r = await view.command(HouseCommand.lock).call((on: on));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  /// Asks house.rooms; a call not done throws [CallNotDone].
  Future<List<String>> rooms({required bool lit}) async {
    final r = await view.query(HouseQuery.rooms).ask((lit: lit));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  /// house.doorbell.rang, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<HouseRang>> get rang => view.fact(HouseFact.rang).stream;

  /// house.motion.seen, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<HouseMotion>> get motion => view.fact(HouseFact.motion).stream;
}

/// The vocabulary of [House]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const houseWords = WordSet('house', [
  ...HouseState.values,
  ...HouseCommand.values,
  ...HouseQuery.values,
  ...HouseFact.values,
]);

typedef HouseSetLight = ({String room, bool on});

Map<String, Object?> _$HouseSetLightTo(HouseSetLight p) => {
  'room': p.room,
  'on': p.on,
};

HouseSetLight _$HouseSetLightFrom(Map<String, Object?> m) =>
    (room: m['room']! as String, on: m['on']! as bool);

typedef HouseSetHeat = ({num target});

Map<String, Object?> _$HouseSetHeatTo(HouseSetHeat p) => {'target': p.target};

HouseSetHeat _$HouseSetHeatFrom(Map<String, Object?> m) =>
    (target: m['target']! as num);

typedef HouseSetMode = ({Mode mode});

Map<String, Object?> _$HouseSetModeTo(HouseSetMode p) => {'mode': p.mode};

HouseSetMode _$HouseSetModeFrom(Map<String, Object?> m) =>
    (mode: m['mode']! as Mode);

typedef HouseLock = ({bool on});

Map<String, Object?> _$HouseLockTo(HouseLock p) => {'on': p.on};

HouseLock _$HouseLockFrom(Map<String, Object?> m) => (on: m['on']! as bool);

typedef HouseRooms = ({bool lit});

Map<String, Object?> _$HouseRoomsTo(HouseRooms p) => {'lit': p.lit};

HouseRooms _$HouseRoomsFrom(Map<String, Object?> m) => (lit: m['lit']! as bool);

typedef HouseRang = ({String who});

Map<String, Object?> _$HouseRangTo(HouseRang p) => {'who': p.who};

HouseRang _$HouseRangFrom(Map<String, Object?> m) => (who: m['who']! as String);

typedef HouseMotion = ({String room});

Map<String, Object?> _$HouseMotionTo(HouseMotion p) => {'room': p.room};

HouseMotion _$HouseMotionFrom(Map<String, Object?> m) =>
    (room: m['room']! as String);

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

/// The owner base of [Visit]: it defines every word, keeps a
/// writer of each state, says each fact by a method of its
/// params, and serves each command and query by a handler to
/// write (`call.inReply`: the cause of what it does in reply).
abstract base class VisitOwner extends Owner {
  /// Writes visit.guests.
  late final StateWriterOf<List<String>> guests;

  @override
  void define(IParticipant p) {
    guests = keep(p.state(VisitState.guests).define());
    keep(p.command(VisitCommand.leave).define(leave));
    defineMore(p);
  }

  /// What [Visit] does not say: kinds, guards, words named at
  /// run time. After its words are defined.
  void defineMore(IParticipant p) {}

  /// Serves visit.leave.
  void leave(CommandCallOf<VisitLeave> call);
}

/// The words of [Visit] as a consumer uses them, through a
/// view: its participant, a `LocalView`, a `MirrorView`.
final class VisitClient {
  const VisitClient(this.view);

  final IRegistryView view;

  /// Whether [word] is there for the view now (SPEC §6.5).
  WordStatus status(IWord word) => view.status(word.name);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => view.statusChanges(word.name);

  /// visit.guests now.
  List<String>? get guests => view.state(VisitState.guests).read();

  /// visit.guests now, then whenever it changes.
  Stream<List<String>?> get guestsChanges =>
      view.state(VisitState.guests).watch();

  /// Calls visit.leave; a call not done throws [CallNotDone].
  Future<void> leave({required String who}) async {
    final r = await view.command(VisitCommand.leave).call((who: who));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }
}

/// The vocabulary of [Visit]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const visitWords = WordSet('visit', [
  ...VisitState.values,
  ...VisitCommand.values,
]);

typedef VisitLeave = ({String who});

Map<String, Object?> _$VisitLeaveTo(VisitLeave p) => {'who': p.who};

VisitLeave _$VisitLeaveFrom(Map<String, Object?> m) =>
    (who: m['who']! as String);
