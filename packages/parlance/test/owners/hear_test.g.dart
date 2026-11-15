// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hear_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The facts of [Door].
enum DoorFact<T> implements IFactWord<T> {
  rang<DoorRang>(
    'door.rang',
    RecordShape<DoorRang>(
      {'who': Part(PlainShape(TextType()))},
      to: _$DoorRangTo,
      from: _$DoorRangFrom,
      get: _$DoorRangAt,
    ),
  );

  const DoorFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The owner base of [Door]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class DoorOwnerBase implements IOwner {
  DoorOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: DoorVocabulary.definition,
    );
  }

  IFactSayerOf<DoorRang>? _$rang;

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    _$rang = p.fact(DoorFact.rang).define();
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }

  /// door.rang: said by `say`.
  late final DoorRangFact rang = DoorRangFact._(this);
}

/// door.rang, as [DoorOwnerBase] says it.
final class DoorRangFact {
  DoorRangFact._(this._base);
  final DoorOwnerBase _base;

  /// Says door.rang; on behalf of [by], when given.
  /// Said while its owner is not attached, no one hears it.
  void say({required String who, Principal? by}) =>
      _base._$rang?.say((who: who), by: by);
}

/// The words of [Door] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IDoorClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IDoorClient({
    required IParticipant participant,
    required Principal target,
  }) = _$DoorClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IDoorClient.of({required IOwner owner, required Principal target}) =
      _$DoorClient._of;

  /// door.rang: what it says from now on, and its messages.
  IFactOf<DoorRang> get rang;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Door] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Door] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$DoorClient implements IDoorClient {
  _$DoorClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      DoorVocabulary.words,
      from: DoorVocabulary.definition.from,
    );
  }

  _$DoorClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      DoorVocabulary.words,
      from: DoorVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IFactOf<DoorRang> get rang => _$words.factOf(DoorFact.rang);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(DoorVocabulary.words);
}

/// The vocabulary of [Door], independent of its publishing target.
abstract final class DoorVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'door';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...DoorFact.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'DoorVocabulary.definition',
  );
}

typedef DoorRang = ({String who});

Map<String, Object?> _$DoorRangTo(DoorRang p) => {'who': p.who};

DoorRang _$DoorRangFrom(Map<String, Object?> m) => (who: m['who']! as String);

Object? _$DoorRangAt(DoorRang p, int i) => p.who;

/// The states of [Book].
enum BookState<T> implements IStateWord<T> {
  last<String>('book.last', PlainShape(TextType()));

  const BookState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The owner base of [Book]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class BookOwnerBase implements IOwner {
  BookOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: BookVocabulary.definition,
    );
  }

  /// book.last: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<String> last = Single<String>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(last, p.state(BookState.last).define());
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(last);
  }
}

/// The words of [Book] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IBookClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IBookClient({
    required IParticipant participant,
    required Principal target,
  }) = _$BookClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IBookClient.of({required IOwner owner, required Principal target}) =
      _$BookClient._of;

  /// book.last: its value now, and its changes.
  IStateOf<String> get last;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Book] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Book] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$BookClient implements IBookClient {
  _$BookClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      BookVocabulary.words,
      from: BookVocabulary.definition.from,
    );
  }

  _$BookClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      BookVocabulary.words,
      from: BookVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IStateOf<String> get last => _$words.stateOf(BookState.last);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(BookVocabulary.words);
}

/// The vocabulary of [Book], independent of its publishing target.
abstract final class BookVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'book';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...BookState.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'BookVocabulary.definition',
  );
}
