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
abstract class DoorsOwnerBase implements IOwner {
  DoorsOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: DoorsVocabulary.definition,
    );
  }

  /// door.room, by door: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<Room> room = Keyed<Room>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
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
/// place.
abstract interface class IDoorsClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IDoorsClient({
    required IParticipant participant,
    required Principal target,
  }) = _$DoorsClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IDoorsClient.of({required IOwner owner, required Principal target}) =
      _$DoorsClient._of;

  /// door.room, by door: each value, and its changes.
  IKeyedOf<Room> get room;

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
final class _$DoorsClient implements IDoorsClient {
  _$DoorsClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      DoorsVocabulary.words,
      from: DoorsVocabulary.definition.from,
    );
  }

  _$DoorsClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      DoorsVocabulary.words,
      from: DoorsVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IKeyedOf<Room> get room => _$words.keyedOf(DoorsState.room);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(DoorsVocabulary.words);
}

/// The vocabulary of [Doors], independent of its publishing target.
abstract final class DoorsVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'door';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...DoorsState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance_generator 0.3.0',
    dartName: 'DoorsVocabulary.definition',
  );
}

const _$RoomShape = RecordShape<Room>(
  {
    'name': Part(PlainShape(TextType()), description: 'Its name.'),
    'floor': Part(PlainShape(IntType())),
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
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: LightsVocabulary.definition,
    );
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
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
/// place.
abstract interface class ILightsClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory ILightsClient({
    required IParticipant participant,
    required Principal target,
  }) = _$LightsClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ILightsClient.of({required IOwner owner, required Principal target}) =
      _$LightsClient._of;

  /// Calls light.on; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> on({required Room room, CancellationToken? cancel});

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
final class _$LightsClient implements ILightsClient {
  _$LightsClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      LightsVocabulary.words,
      from: LightsVocabulary.definition.from,
    );
  }

  _$LightsClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      LightsVocabulary.words,
      from: LightsVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  Future<void> on({required Room room, CancellationToken? cancel}) async {
    final r = await _$words.command(LightsCommand.on).call((
      room: room,
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
      _$words.mismatches(LightsVocabulary.words);
}

/// The vocabulary of [Lights], independent of its publishing target.
abstract final class LightsVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'light';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...LightsCommand.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance_generator 0.3.0',
    dartName: 'LightsVocabulary.definition',
  );
}

typedef LightsOn = ({Room room});

Map<String, Object?> _$LightsOnTo(LightsOn p) => {'room': p.room};

LightsOn _$LightsOnFrom(Map<String, Object?> m) => (room: m['room']! as Room);

Object? _$LightsOnAt(LightsOn p, int i) => p.room;
