// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'owner_tools_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Lamp].
enum LampState<T> implements IStateWord<T> {
  level<int>('lamp.level', PlainShape(IntType()));

  const LampState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
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

  /// lamp.level: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<int> level = Single<int>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Single.attach(level, p.state(LampState.level).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(level);
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

  /// lamp.level: its value now, and its changes.
  IStateOf<int> get level;

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
  IStateOf<int> get level => _$words.stateOf(LampState.level);

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
