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
    IOwner.made(this, define: _$define, write: _$write, vocabulary: doorWords);
  }

  IFactSayerOf<DoorRang>? _$rang;

  void _$say<T>(String fact, IFactSayerOf<T>? e, T payload, Principal? by) {
    if (e == null) {
      IOwner.said(this, fact, payload);
    } else {
      e.say(payload, by: by);
    }
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
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
  void say({required String who, Principal? by}) =>
      _base._$say('door.rang', _base._$rang, (who: who), by);
}

/// The words of [Door] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IDoorClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IDoorClient(IParticipant participant) = _$DoorClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IDoorClient.of(IOwner owner) = _$DoorClient._of;

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
  _$DoorClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(doorWords.words, from: doorWords.from);
  }

  _$DoorClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(doorWords.words, from: doorWords.from);
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
      _$words.mismatches(doorWords.words);
}

/// The vocabulary of [Door]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const doorWords = WordSet(
  'door',
  [...DoorFact.values],
  from: 'parlance',
  dartName: 'doorWords',
);

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
    IOwner.made(this, define: _$define, write: _$write, vocabulary: bookWords);
  }

  /// book.last: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<String> last = Single<String>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
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
  factory IBookClient(IParticipant participant) = _$BookClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IBookClient.of(IOwner owner) = _$BookClient._of;

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
  _$BookClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(bookWords.words, from: bookWords.from);
  }

  _$BookClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(bookWords.words, from: bookWords.from);
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
      _$words.mismatches(bookWords.words);
}

/// The vocabulary of [Book]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const bookWords = WordSet(
  'book',
  [...BookState.values],
  from: 'parlance',
  dartName: 'bookWords',
);
