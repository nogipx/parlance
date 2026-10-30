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

/// The kinds of choices [Test] speaks of: what an owner gives by
/// `choices(TestChoices.dial, ...)`.
abstract final class TestChoices {
  static const String dial = 'dial';
}

/// The owner base of [Test]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class TestOwnerBase implements IOwner {
  TestOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: testWords);
  }

  /// test.level, by dial: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<num> level = Keyed<num>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
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
  factory ITestClient(IParticipant participant) = _$TestClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ITestClient.of(IOwner owner) = _$TestClient._of;

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
  _$TestClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(testWords.words, from: testWords.from);
  }

  _$TestClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(testWords.words, from: testWords.from);
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
      _$words.mismatches(testWords.words);
}

/// The vocabulary of [Test]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const testWords = WordSet(
  'test',
  [...TestState.values],
  from: 'parlance',
  dartName: 'testWords',
);

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
    IOwner.made(this, define: _$define, write: _$write, vocabulary: flagWords);
  }

  /// flag.on: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<bool> on = Single<bool>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
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
  factory IFlagClient(IParticipant participant) = _$FlagClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IFlagClient.of(IOwner owner) = _$FlagClient._of;

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
  _$FlagClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(flagWords.words, from: flagWords.from);
  }

  _$FlagClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(flagWords.words, from: flagWords.from);
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
      _$words.mismatches(flagWords.words);
}

/// The vocabulary of [Flag]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const flagWords = WordSet(
  'flag',
  [...FlagState.values],
  from: 'parlance',
  dartName: 'flagWords',
);

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
      vocabulary: knobWordsWords,
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
  factory IKnobWordsClient(IParticipant participant) = _$KnobWordsClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IKnobWordsClient.of(IOwner owner) = _$KnobWordsClient._of;

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
  _$KnobWordsClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(knobWordsWords.words, from: knobWordsWords.from);
  }

  _$KnobWordsClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(knobWordsWords.words, from: knobWordsWords.from);
  }

  final GeneratedWords _$words;

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(knobWordsWords.words);
}

/// The vocabulary of [KnobWords]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const knobWordsWords = WordSet(
  'knob',
  [],
  from: 'parlance',
  dartName: 'knobWordsWords',
);
