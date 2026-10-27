/// The house's vocabulary: every state, command and fact, named once with
/// its Dart types. The rest of the code only ever refers to these.
library;

import 'package:parlance/registry.dart';

/// Who acts in the house.
abstract final class Who {
  static const house = Principal('house');
  static const ann = Principal('resident', 'ann');
  static const bob = Principal('guest', 'bob');
  static Principal phone(String name) => Principal('phone', name);
  static Principal agent(String session) => Principal('agent', session);

  /// The module that keeps a visit, and the garden's.
  static const visit = Principal('module', 'visit');
  static const garden = Principal('module', 'garden');

  /// The kinds that may override an overridable guard.
  static const overriders = {'resident'};

  /// Residents, their phones and agents, links, and the house itself.
  static const household = Callers({
    'resident': Access.allow,
    'phone': Access.allow,
    'agent': Access.allow,
    'link': Access.allow,
    'house': Access.allow,
    'system': Access.allow,
  });

  /// [household], and guests with a warning in an editor.
  static const anyone = Callers({
    'resident': Access.allow,
    'phone': Access.allow,
    'agent': Access.allow,
    'link': Access.allow,
    'house': Access.allow,
    'system': Access.allow,
    'guest': Access.warn,
  });

  /// The residents and their phones: who changes links.
  static const residents = Callers({
    'resident': Access.allow,
    'phone': Access.allow,
  });
}

/// The entity kind of rooms.
const room = 'room';

enum Mode { home, away, night }

/// The house's states.
enum HouseState<T> implements IStateWord<T> {
  /// Whether a room's light is on, by room.
  light<bool>('light.on', Plain(BoolType()), key: room),

  /// The heating's target, °C.
  heat<num>('heat.target', Plain(NumType(min: 10, max: 28))),
  mode<Mode>('house.mode', EnumShape(Mode.values)),
  locked<bool>('door.locked', Plain(BoolType()));

  const HouseState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

typedef SetLight = ({String room, bool on});
typedef SetHeat = ({num target});
typedef SetMode = ({Mode mode});
typedef Lock = ({bool on});

/// The house's commands.
enum HouseCommand<P, R> implements ICommandWord<P, R> {
  setLight<SetLight, void>(
    'light.set',
    RecordShape(
      {'room': Part(Plain(RefType(room))), 'on': Part(Plain(BoolType()))},
      to: _lightTo,
      from: _lightFrom,
    ),
  ),
  setHeat<SetHeat, void>(
    'heat.set',
    RecordShape(
      {'target': Part(Plain(NumType(min: 10, max: 28)))},
      to: _heatTo,
      from: _heatFrom,
    ),
  ),
  setMode<SetMode, void>(
    'house.mode.set',
    RecordShape(
      {'mode': Part(EnumShape(Mode.values))},
      to: _modeTo,
      from: _modeFrom,
    ),
  ),

  /// Locks (on) or unlocks the door.
  lock<Lock, void>(
    'door.lock',
    RecordShape({'on': Part(Plain(BoolType()))}, to: _lockTo, from: _lockFrom),
  );

  const HouseCommand(this.name, this.params);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  Shape<R>? get returns => null;
}

typedef Rooms = ({bool lit});

/// What the house is asked: questions that change nothing.
enum HouseQuery<P, R> implements IQueryWord<P, R> {
  /// The rooms whose light is on ([Rooms.lit]) or off.
  rooms<Rooms, List<String>>(
    'house.rooms',
    RecordShape(
      {'lit': Part(Plain(BoolType()))},
      to: _roomsTo,
      from: _roomsFrom,
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

typedef Ring = ({String who});
typedef Motion = ({String room});

/// What happens in the house.
enum HouseFact<T> implements IFactWord<T> {
  /// Someone rang the doorbell.
  rang<Ring>(
    'doorbell.rang',
    RecordShape({'who': Part(Plain(TextType()))}, to: _ringTo, from: _ringFrom),
  ),

  /// A sensor saw someone in a room.
  motion<Motion>(
    'motion.seen',
    RecordShape(
      {'room': Part(Plain(TextType()))},
      to: _motionTo,
      from: _motionFrom,
    ),
  );

  const HouseFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

Map<String, Object?> _lightTo(SetLight p) => {'room': p.room, 'on': p.on};
SetLight _lightFrom(Map<String, Object?> m) =>
    (room: m['room']! as String, on: m['on']! as bool);
Map<String, Object?> _heatTo(SetHeat p) => {'target': p.target};
SetHeat _heatFrom(Map<String, Object?> m) => (target: m['target']! as num);
Map<String, Object?> _modeTo(SetMode p) => {'mode': p.mode};
SetMode _modeFrom(Map<String, Object?> m) => (mode: m['mode']! as Mode);
Map<String, Object?> _lockTo(Lock p) => {'on': p.on};
Lock _lockFrom(Map<String, Object?> m) => (on: m['on']! as bool);
Map<String, Object?> _roomsTo(Rooms r) => {'lit': r.lit};
Rooms _roomsFrom(Map<String, Object?> m) => (lit: m['lit']! as bool);
Map<String, Object?> _ringTo(Ring r) => {'who': r.who};
Ring _ringFrom(Map<String, Object?> m) => (who: m['who']! as String);
Map<String, Object?> _motionTo(Motion r) => {'room': r.room};
Motion _motionFrom(Map<String, Object?> m) => (room: m['room']! as String);

/// A visit's words: who is in, and seeing a guest out. They are there only
/// while a visit is (a scope, `main.dart`).
enum VisitState<T> implements IStateWord<T> {
  guests<List<String>>('visit.guests', ListShape(Plain(TextType())));

  const VisitState(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

typedef Leave = ({String who});

enum VisitCommand<P, R> implements ICommandWord<P, R> {
  leave<Leave, void>(
    'visit.leave',
    RecordShape(
      {'who': Part(Plain(TextType()))},
      to: _leaveTo,
      from: _leaveFrom,
    ),
  );

  const VisitCommand(this.name, this.params);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  Shape<R>? get returns => null;
}

/// A weather station's word, of a house that has none.
enum WeatherState<T> implements IStateWord<T> {
  rain<bool>('weather.rain', Plain(BoolType()));

  const WeatherState(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

Map<String, Object?> _leaveTo(Leave l) => {'who': l.who};
Leave _leaveFrom(Map<String, Object?> m) => (who: m['who']! as String);
