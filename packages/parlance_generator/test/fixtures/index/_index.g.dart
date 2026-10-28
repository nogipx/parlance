// GENERATED CODE - DO NOT MODIFY BY HAND

part of '_index.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Doors].
enum DoorsState<T> implements IStateWord<T> {
  room<Room>('door.room', _$RoomShape, key: 'door');

  const DoorsState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The owner base of [Doors]: it defines every word, keeps a
/// writer of each state, says each fact by a method of its
/// params, and serves each command and query by a handler to
/// write (`call.inReply`: the cause of what it does in reply).
abstract base class DoorsOwner extends Owner {
  /// Writes door.room.
  late final StateWriterOf<Room> room;

  @override
  void define(IParticipant p) {
    room = keep(p.state(DoorsState.room).define());
    defineMore(p);
  }

  /// What [Doors] does not say: kinds, guards, words named at
  /// run time. After its words are defined.
  void defineMore(IParticipant p) {}
}

/// The words of [Doors] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [DoorsClient] is them over a view.
abstract interface class IDoorsClient {
  /// door.room of [door] now.
  Room? roomOf(String door);

  /// door.room of every door, by key.
  Map<String?, Room> get roomAll;

  /// door.room of [door] now, then on every change.
  Stream<Room?> roomChanges(String door);
}

/// The words of [Doors] through a view: its participant, a
/// `LocalView`, a `MirrorView`.
final class DoorsClient implements IDoorsClient {
  const DoorsClient(this.view);

  final IRegistryView view;

  @override
  Room? roomOf(String door) => view.state(DoorsState.room).read(key: door);

  @override
  Map<String?, Room> get roomAll => view.state(DoorsState.room).readAll();

  @override
  Stream<Room?> roomChanges(String door) =>
      view.state(DoorsState.room).watch(key: door);

  /// Whether [word] is there for the view now (SPEC §6.5).
  WordStatus status(IWord word) => view.status(word.name);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => view.statusChanges(word.name);
}

/// The vocabulary of [Doors]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const doorsWords = WordSet('door', [...DoorsState.values]);

const _$RoomShape = RecordShape<Room>(
  {
    'name': Part(Plain(TextType()), description: 'Its name.'),
    'floor': Part(Plain(IntType())),
  },
  to: _$RoomTo,
  from: _$RoomFrom,
  get: _$RoomAt,
);

Map<String, Object?> _$RoomTo(Room v) => {'name': v.name, 'floor': v.floor};

Room _$RoomFrom(Map<String, Object?> m) =>
    (name: m['name']! as String, floor: m['floor']! as int);

Object? _$RoomAt(Room v, int i) => switch (i) {
  0 => v.name,
  _ => v.floor,
};

/// The commands of [Lights].
enum LightsCommand<P, R> implements ICommandWord<P, R> {
  on<LightsOn, void>(
    'light.on',
    RecordShape<LightsOn>(
      {'room': Part(_$RoomShape)},
      to: _$LightsOnTo,
      from: _$LightsOnFrom,
      get: _$LightsOnAt,
    ),
    null,
  );

  const LightsCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The owner base of [Lights]: it defines every word, keeps a
/// writer of each state, says each fact by a method of its
/// params, and serves each command and query by a handler to
/// write (`call.inReply`: the cause of what it does in reply).
abstract base class LightsOwner extends Owner {
  @override
  void define(IParticipant p) {
    keep(p.command(LightsCommand.on).define(on));
    defineMore(p);
  }

  /// What [Lights] does not say: kinds, guards, words named at
  /// run time. After its words are defined.
  void defineMore(IParticipant p) {}

  /// Serves light.on.
  void on(CommandCallOf<LightsOn> call);
}

/// The words of [Lights] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [LightsClient] is them over a view.
abstract interface class ILightsClient {
  /// Calls light.on; a call not done throws [CallNotDone].
  Future<void> on({required Room room});
}

/// The words of [Lights] through a view: its participant, a
/// `LocalView`, a `MirrorView`.
final class LightsClient implements ILightsClient {
  const LightsClient(this.view);

  final IRegistryView view;

  @override
  Future<void> on({required Room room}) async {
    final r = await view.command(LightsCommand.on).call((room: room));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  /// Whether [word] is there for the view now (SPEC §6.5).
  WordStatus status(IWord word) => view.status(word.name);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => view.statusChanges(word.name);
}

/// The vocabulary of [Lights]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const lightsWords = WordSet('light', [...LightsCommand.values]);

typedef LightsOn = ({Room room});

Map<String, Object?> _$LightsOnTo(LightsOn p) => {'room': p.room};

LightsOn _$LightsOnFrom(Map<String, Object?> m) => (room: m['room']! as Room);

Object? _$LightsOnAt(LightsOn p, int i) => p.room;
