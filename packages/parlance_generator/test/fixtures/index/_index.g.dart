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

/// The owner base of [Doors]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract base class DoorsOwner extends Owner {
  DoorsOwner() {
    Owner.made(this, define: _define, write: _write);
  }

  /// door.room, by door: what this owner set of each,
  /// read and written as a map is.
  final Keyed<Room> room = Keyed<Room>();

  void _define(IParticipant p) {
    Keyed.attach(room, keep(p.state(DoorsState.room).define()));
    defineMore(p);
  }

  /// What it set before it was attached, written once it is.
  var _written = false;
  void _write() {
    if (_written) return;
    _written = true;
    Keyed.writeAll(room);
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
/// `LocalView`, a `MirrorView`. Made, it tells the registry
/// the code was built against them, for it to say where one
/// is defined otherwise (SPEC §6.9).
final class DoorsClient implements IDoorsClient {
  DoorsClient(this.view) {
    view.builtAgainst(doorsWords.words, from: doorsWords.from);
  }

  final IRegistryView view;

  @override
  Room? roomOf(String door) => view.state(DoorsState.room).read(key: door);

  @override
  Map<String?, Room> get roomAll => view.state(DoorsState.room).readAll();

  @override
  Stream<Room?> roomChanges(String door) =>
      view.state(DoorsState.room).watch(key: door);

  /// Whether [word] is there for the view now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word) => wordStatus(view, word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => wordStatusChanges(view, word);

  /// Each word of [Doors] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches =>
      wordMismatches(view, doorsWords.words);
}

/// The vocabulary of [Doors]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const doorsWords = WordSet('door', [
  ...DoorsState.values,
], from: 'parlance_generator');

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

/// The owner base of [Lights]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract base class LightsOwner extends Owner {
  LightsOwner() {
    Owner.made(this, define: _define, write: _write);
  }

  void _define(IParticipant p) {
    keep(p.command(LightsCommand.on).define((c) => on(room: c.params.room)));
    defineMore(p);
  }

  /// What it set before it was attached, written once it is.
  var _written = false;
  void _write() {
    if (_written) return;
    _written = true;
  }

  /// What [Lights] does not say: kinds, guards, words named at
  /// run time. After its words are defined.
  void defineMore(IParticipant p) {}

  /// Serves light.on.
  void on({required Room room});
}

/// The words of [Lights] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [LightsClient] is them over a view.
abstract interface class ILightsClient {
  /// Calls light.on; a call not done throws [CallNotDone].
  Future<void> on({required Room room});
}

/// The words of [Lights] through a view: its participant, a
/// `LocalView`, a `MirrorView`. Made, it tells the registry
/// the code was built against them, for it to say where one
/// is defined otherwise (SPEC §6.9).
final class LightsClient implements ILightsClient {
  LightsClient(this.view) {
    view.builtAgainst(lightsWords.words, from: lightsWords.from);
  }

  final IRegistryView view;

  @override
  Future<void> on({required Room room}) async {
    final r = await view.command(LightsCommand.on).call((room: room));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  /// Whether [word] is there for the view now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word) => wordStatus(view, word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => wordStatusChanges(view, word);

  /// Each word of [Lights] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches =>
      wordMismatches(view, lightsWords.words);
}

/// The vocabulary of [Lights]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const lightsWords = WordSet('light', [
  ...LightsCommand.values,
], from: 'parlance_generator');

typedef LightsOn = ({Room room});

Map<String, Object?> _$LightsOnTo(LightsOn p) => {'room': p.room};

LightsOn _$LightsOnFrom(Map<String, Object?> m) => (room: m['room']! as Room);

Object? _$LightsOnAt(LightsOn p, int i) => p.room;
