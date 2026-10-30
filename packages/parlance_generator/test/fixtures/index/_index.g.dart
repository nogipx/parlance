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

/// The kinds of choices [Doors] speaks of: what an owner gives by
/// `choices(DoorsChoices.door, ...)`.
abstract final class DoorsChoices {
  static const String door = 'door';
}

/// The owner base of [Doors]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class DoorsOwnerBase implements IOwner {
  DoorsOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, words: doorsWords);
  }

  /// door.room, by door: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<Room> room = Keyed<Room>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.of(participant);
    Keyed.attach(room, p.state(DoorsState.room).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Keyed.writeAll(room);
  }
}

/// The words of [Doors] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [DoorsClient] is them over a participant.
abstract interface class IDoorsClient {
  /// door.room of [door] now.
  Room? roomOf(String door);

  /// door.room of every door, by key.
  Map<String, Room> get roomAll;

  /// door.room of [door] now, then on every change.
  Stream<Room?> roomChanges(String door);

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Doors] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Doors] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class DoorsClient implements IDoorsClient {
  DoorsClient(IParticipant participant)
    : _$words = GeneratedWords.of(participant) {
    _$words.builtAgainst(doorsWords.words, from: doorsWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  DoorsClient.of(IOwner owner) : _$words = GeneratedWords.ofOwner(owner) {
    _$words.builtAgainst(doorsWords.words, from: doorsWords.from);
  }

  final GeneratedWords _$words;

  @override
  Room? roomOf(String door) => _$words.state(DoorsState.room).read(key: door);

  @override
  Map<String, Room> get roomAll => {
    for (final MapEntry(:key, :value)
        in _$words.state(DoorsState.room).readAll().entries)
      ?key: value,
  };

  @override
  Stream<Room?> roomChanges(String door) =>
      _$words.later(() => _$words.state(DoorsState.room).watch(key: door));

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(doorsWords.words);
}

/// The vocabulary of [Doors]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const doorsWords = WordSet(
  'door',
  [...DoorsState.values],
  from: 'parlance_generator',
  dartName: 'doorsWords',
);

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
abstract class LightsOwnerBase implements IOwner {
  LightsOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, words: lightsWords);
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords.of(participant);
    p.command(LightsCommand.on).serve((x) => on(room: x.room));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }

  /// Serves light.on.
  void on({required Room room});
}

/// The words of [Lights] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [LightsClient] is them over a participant.
abstract interface class ILightsClient {
  /// Calls light.on; a call not done throws [CallNotDone].
  Future<void> on({required Room room});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Lights] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Lights] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class LightsClient implements ILightsClient {
  LightsClient(IParticipant participant)
    : _$words = GeneratedWords.of(participant) {
    _$words.builtAgainst(lightsWords.words, from: lightsWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  LightsClient.of(IOwner owner) : _$words = GeneratedWords.ofOwner(owner) {
    _$words.builtAgainst(lightsWords.words, from: lightsWords.from);
  }

  final GeneratedWords _$words;

  @override
  Future<void> on({required Room room}) async {
    final r = await _$words.command(LightsCommand.on).call((room: room));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(lightsWords.words);
}

/// The vocabulary of [Lights]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const lightsWords = WordSet(
  'light',
  [...LightsCommand.values],
  from: 'parlance_generator',
  dartName: 'lightsWords',
);

typedef LightsOn = ({Room room});

Map<String, Object?> _$LightsOnTo(LightsOn p) => {'room': p.room};

LightsOn _$LightsOnFrom(Map<String, Object?> m) => (room: m['room']! as Room);

Object? _$LightsOnAt(LightsOn p, int i) => p.room;
