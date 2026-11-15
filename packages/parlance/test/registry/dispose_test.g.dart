// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dispose_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Lamp].
enum LampState<T> implements IStateWord<T> {
  on<bool>('lamp.on', PlainShape(BoolType()));

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
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: LampVocabulary.definition,
    );
  }

  /// lamp.on: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<bool> on = Single<bool>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(on, p.state(LampState.on).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(on);
  }
}

/// The words of [Lamp] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class ILampClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory ILampClient({
    required IParticipant participant,
    required Principal target,
  }) = _$LampClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ILampClient.of({required IOwner owner, required Principal target}) =
      _$LampClient._of;

  /// lamp.on: its value now, and its changes.
  IStateOf<bool> get on;

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
  _$LampClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      LampVocabulary.words,
      from: LampVocabulary.definition.from,
    );
  }

  _$LampClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      LampVocabulary.words,
      from: LampVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IStateOf<bool> get on => _$words.stateOf(LampState.on);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(LampVocabulary.words);
}

/// The vocabulary of [Lamp], independent of its publishing target.
abstract final class LampVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'lamp';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...LampState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.3.0',
    dartName: 'LampVocabulary.definition',
  );
}
