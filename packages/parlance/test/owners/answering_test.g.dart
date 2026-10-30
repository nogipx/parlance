// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'answering_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Room].
enum RoomState<T> implements IStateWord<T> {
  heat<int>('room.heat', PlainShape(IntType())),
  lamp<bool>('room.lamp', PlainShape(BoolType()));

  const RoomState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Room].
enum RoomCommand<P, R> implements ICommandWord<P, R> {
  warm<(), void>('room.warm', RecordShape.none, null);

  const RoomCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The owner base of [Room]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class RoomOwnerBase implements IOwner {
  RoomOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: roomWords);
  }

  /// room.heat: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<int> heat = Single<int>();

  /// room.lamp: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<bool> lamp = Single<bool>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Single.attach(heat, p.state(RoomState.heat).define());
    Single.attach(lamp, p.state(RoomState.lamp).define());
    p
        .command(RoomCommand.warm)
        .serve((_) => warm(), callers: const Callers({'user': Access.allow}));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(heat);
    Single.write(lamp);
  }

  /// Serves room.warm.
  void warm();
}

/// The words of [Room] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IRoomClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IRoomClient(IParticipant participant) = _$RoomClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IRoomClient.of(IOwner owner) = _$RoomClient._of;

  /// room.heat: its value now, and its changes.
  IStateOf<int> get heat;

  /// room.lamp: its value now, and its changes.
  IStateOf<bool> get lamp;

  /// Calls room.warm; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> warm({CancellationToken? cancel});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Room] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Room] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$RoomClient implements IRoomClient {
  _$RoomClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(roomWords.words, from: roomWords.from);
  }

  _$RoomClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(roomWords.words, from: roomWords.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<int> get heat => _$words.stateOf(RoomState.heat);

  @override
  IStateOf<bool> get lamp => _$words.stateOf(RoomState.lamp);

  @override
  Future<void> warm({CancellationToken? cancel}) async {
    final r = await _$words.command(RoomCommand.warm).call((), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(roomWords.words);
}

/// The vocabulary of [Room]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const roomWords = WordSet(
  'room',
  [...RoomState.values, ...RoomCommand.values],
  from: 'parlance',
  dartName: 'roomWords',
);
