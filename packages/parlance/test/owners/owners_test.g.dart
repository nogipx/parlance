// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'owners_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Test].
enum TestState<T> implements IStateWord<T> {
  level<num>('test.level', PlainShape(NumType()), key: 'dial');

  const TestState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The owner base of [Test]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class TestOwnerBase implements IOwner {
  TestOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: TestVocabulary.definition,
    );
  }

  /// test.level, by dial: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<num> level = Keyed<num>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Keyed.attach(level, p.state(TestState.level).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Keyed.writeAll(level);
  }
}

/// The words of [Test] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class ITestClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory ITestClient({
    required IParticipant participant,
    required Principal target,
  }) = _$TestClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ITestClient.of({required IOwner owner, required Principal target}) =
      _$TestClient._of;

  /// test.level, by dial: each value, and its changes.
  IKeyedOf<num> get level;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Test] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Test] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$TestClient implements ITestClient {
  _$TestClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      TestVocabulary.words,
      from: TestVocabulary.definition.from,
    );
  }

  _$TestClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      TestVocabulary.words,
      from: TestVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IKeyedOf<num> get level => _$words.keyedOf(TestState.level);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(TestVocabulary.words);
}

/// The vocabulary of [Test], independent of its publishing target.
abstract final class TestVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'test';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...TestState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'TestVocabulary.definition',
  );
}

/// The states of [Flag].
enum FlagState<T> implements IStateWord<T> {
  on<bool>('flag.on', PlainShape(BoolType()));

  const FlagState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The owner base of [Flag]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class FlagOwnerBase implements IOwner {
  FlagOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: FlagVocabulary.definition,
    );
  }

  /// flag.on: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<bool> on = Single<bool>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(on, p.state(FlagState.on).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(on);
  }
}

/// The words of [Flag] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IFlagClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IFlagClient({
    required IParticipant participant,
    required Principal target,
  }) = _$FlagClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IFlagClient.of({required IOwner owner, required Principal target}) =
      _$FlagClient._of;

  /// flag.on: its value now, and its changes.
  IStateOf<bool> get on;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Flag] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Flag] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$FlagClient implements IFlagClient {
  _$FlagClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      FlagVocabulary.words,
      from: FlagVocabulary.definition.from,
    );
  }

  _$FlagClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      FlagVocabulary.words,
      from: FlagVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IStateOf<bool> get on => _$words.stateOf(FlagState.on);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(FlagVocabulary.words);
}

/// The vocabulary of [Flag], independent of its publishing target.
abstract final class FlagVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'flag';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...FlagState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'FlagVocabulary.definition',
  );
}

/// The owner base of [KnobWords]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class KnobWordsOwnerBase implements IOwner {
  KnobWordsOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: KnobWordsVocabulary.definition,
    );
  }

  void _$define(IParticipant participant) {}

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }
}

/// The words of [KnobWords] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IKnobWordsClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IKnobWordsClient({
    required IParticipant participant,
    required Principal target,
  }) = _$KnobWordsClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IKnobWordsClient.of({
    required IOwner owner,
    required Principal target,
  }) = _$KnobWordsClient._of;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [KnobWords] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [KnobWords] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$KnobWordsClient implements IKnobWordsClient {
  _$KnobWordsClient({
    required IParticipant participant,
    required Principal target,
  }) : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      KnobWordsVocabulary.words,
      from: KnobWordsVocabulary.definition.from,
    );
  }

  _$KnobWordsClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      KnobWordsVocabulary.words,
      from: KnobWordsVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(KnobWordsVocabulary.words);
}

/// The vocabulary of [KnobWords], independent of its publishing target.
abstract final class KnobWordsVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'knob';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'KnobWordsVocabulary.definition',
  );
}
