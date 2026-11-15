// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'owner_group_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [A].
enum AState<T> implements IStateWord<T> {
  level<int>('a.level', PlainShape(IntType()));

  const AState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The owner base of [A]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class AOwnerBase implements IOwner {
  AOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: AVocabulary.definition,
    );
  }

  /// a.level: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<int> level = Single<int>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(level, p.state(AState.level).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(level);
  }
}

/// The words of [A] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IAClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IAClient({
    required IParticipant participant,
    required Principal target,
  }) = _$AClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IAClient.of({required IOwner owner, required Principal target}) =
      _$AClient._of;

  /// a.level: its value now, and its changes.
  IStateOf<int> get level;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [A] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [A] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$AClient implements IAClient {
  _$AClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(AVocabulary.words, from: AVocabulary.definition.from);
  }

  _$AClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(AVocabulary.words, from: AVocabulary.definition.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<int> get level => _$words.stateOf(AState.level);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(AVocabulary.words);
}

/// The vocabulary of [A], independent of its publishing target.
abstract final class AVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'a';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...AState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.3.0',
    dartName: 'AVocabulary.definition',
  );
}

/// The states of [B].
enum BState<T> implements IStateWord<T> {
  level<int>('b.level', PlainShape(IntType()));

  const BState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The owner base of [B]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class BOwnerBase implements IOwner {
  BOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: BVocabulary.definition,
    );
  }

  /// b.level: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<int> level = Single<int>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(level, p.state(BState.level).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(level);
  }
}

/// The words of [B] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IBClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IBClient({
    required IParticipant participant,
    required Principal target,
  }) = _$BClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IBClient.of({required IOwner owner, required Principal target}) =
      _$BClient._of;

  /// b.level: its value now, and its changes.
  IStateOf<int> get level;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [B] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [B] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$BClient implements IBClient {
  _$BClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(BVocabulary.words, from: BVocabulary.definition.from);
  }

  _$BClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(BVocabulary.words, from: BVocabulary.definition.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<int> get level => _$words.stateOf(BState.level);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(BVocabulary.words);
}

/// The vocabulary of [B], independent of its publishing target.
abstract final class BVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'b';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...BState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.3.0',
    dartName: 'BVocabulary.definition',
  );
}

/// The states of [C].
enum CState<T> implements IStateWord<T> {
  level<int>('c.level', PlainShape(IntType()));

  const CState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The owner base of [C]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class COwnerBase implements IOwner {
  COwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: CVocabulary.definition,
    );
  }

  /// c.level: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<int> level = Single<int>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(level, p.state(CState.level).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(level);
  }
}

/// The words of [C] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class ICClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory ICClient({
    required IParticipant participant,
    required Principal target,
  }) = _$CClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ICClient.of({required IOwner owner, required Principal target}) =
      _$CClient._of;

  /// c.level: its value now, and its changes.
  IStateOf<int> get level;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [C] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [C] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$CClient implements ICClient {
  _$CClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(CVocabulary.words, from: CVocabulary.definition.from);
  }

  _$CClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(CVocabulary.words, from: CVocabulary.definition.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<int> get level => _$words.stateOf(CState.level);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(CVocabulary.words);
}

/// The vocabulary of [C], independent of its publishing target.
abstract final class CVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'c';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...CState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.3.0',
    dartName: 'CVocabulary.definition',
  );
}
