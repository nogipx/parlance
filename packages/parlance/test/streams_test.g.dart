// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'streams_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The server streams of [Data].
enum DataServerStream<P, T> implements IServerStreamWord<P, T> {
  numbers<DataNumbers, int>(
    'data.numbers',
    RecordShape<DataNumbers>(
      {
        'start': Part(PlainShape(IntType())),
        'count': Part(PlainShape(IntType()), defaultValue: 3),
      },
      to: _$DataNumbersTo,
      from: _$DataNumbersFrom,
      get: _$DataNumbersAt,
    ),
    PlainShape(IntType()),
  ),
  shared<(), int>('data.shared', RecordShape.none, PlainShape(IntType())),
  caller<(), String>('data.caller', RecordShape.none, PlainShape(TextType())),
  nullable<(), int?>(
    'data.nullable',
    RecordShape.none,
    NullableShape<int>(PlainShape(IntType())),
  ),
  readings<DataReadings, Reading>(
    'data.readings',
    RecordShape<DataReadings>(
      {
        'from': Part(
          JsonShape<Reading>(
            from: Reading.fromJson,
            to: _$DataReadingToJson,
            type: RecordType({'value': Field(IntType())}),
          ),
        ),
      },
      to: _$DataReadingsTo,
      from: _$DataReadingsFrom,
      get: _$DataReadingsAt,
    ),
    JsonShape<Reading>(
      from: Reading.fromJson,
      to: _$DataReadingToJson,
      type: RecordType({'value': Field(IntType())}),
    ),
  ),
  private<(), int>('data.private', RecordShape.none, PlainShape(IntType()));

  const DataServerStream(this.name, this.params, this.shape);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<T> shape;
}

/// The owner base of [Data]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class DataOwnerBase implements IOwner {
  DataOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: dataWords);
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    p
        .serverStream(DataServerStream.numbers)
        .serve(
          (x) => numbers(start: x.start, count: x.count),
          whyNot: whyNotNumbers,
        );
    p.serverStream(DataServerStream.shared).serve((_) => shared());
    p.serverStream(DataServerStream.caller).serve((_) => caller());
    p.serverStream(DataServerStream.nullable).serve((_) => nullable());
    p
        .serverStream(DataServerStream.readings)
        .serve((x) => readings(from: x.from));
    p
        .serverStream(DataServerStream.private)
        .serve(
          (_) => private(),
          readers: const Callers({'admin': Access.allow}),
        );
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }

  /// Provides data.numbers for one subscription.
  Stream<int> numbers({required int start, int count = 3});

  /// Why a subscription cannot open now; null when ready.
  String? whyNotNumbers();

  /// Provides data.shared for one subscription.
  Stream<int> shared();

  /// Provides data.caller for one subscription.
  Stream<String> caller();

  /// Provides data.nullable for one subscription.
  Stream<int?> nullable();

  /// Provides data.readings for one subscription.
  Stream<Reading> readings({required Reading from});

  /// Provides data.private for one subscription.
  Stream<int> private();
}

/// The words of [Data] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IDataClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IDataClient(IParticipant participant) = _$DataClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IDataClient.of(IOwner owner) = _$DataClient._of;

  /// data.numbers: opens on listen; cancellation ends this operation.
  Stream<int> numbers({
    required int start,
    int count = 3,
    CancellationToken? cancel,
  });

  /// data.shared: opens on listen; cancellation ends this operation.
  Stream<int> shared({CancellationToken? cancel});

  /// data.caller: opens on listen; cancellation ends this operation.
  Stream<String> caller({CancellationToken? cancel});

  /// data.nullable: opens on listen; cancellation ends this operation.
  Stream<int?> nullable({CancellationToken? cancel});

  /// data.readings: opens on listen; cancellation ends this operation.
  Stream<Reading> readings({required Reading from, CancellationToken? cancel});

  /// data.private: opens on listen; cancellation ends this operation.
  Stream<int> private({CancellationToken? cancel});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Data] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Data] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$DataClient implements IDataClient {
  _$DataClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(dataWords.words, from: dataWords.from);
  }

  _$DataClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(dataWords.words, from: dataWords.from);
  }

  final GeneratedWords _$words;

  @override
  Stream<int> numbers({
    required int start,
    int count = 3,
    CancellationToken? cancel,
  }) => _$words.serverStream(DataServerStream.numbers).open((
    start: start,
    count: count,
  ), cancel: cancel);

  @override
  Stream<int> shared({CancellationToken? cancel}) =>
      _$words.serverStream(DataServerStream.shared).open((), cancel: cancel);

  @override
  Stream<String> caller({CancellationToken? cancel}) =>
      _$words.serverStream(DataServerStream.caller).open((), cancel: cancel);

  @override
  Stream<int?> nullable({CancellationToken? cancel}) =>
      _$words.serverStream(DataServerStream.nullable).open((), cancel: cancel);

  @override
  Stream<Reading> readings({
    required Reading from,
    CancellationToken? cancel,
  }) => _$words.serverStream(DataServerStream.readings).open((
    from: from,
  ), cancel: cancel);

  @override
  Stream<int> private({CancellationToken? cancel}) =>
      _$words.serverStream(DataServerStream.private).open((), cancel: cancel);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(dataWords.words);
}

/// The vocabulary of [Data]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const dataWords = WordSet(
  'data',
  [...DataServerStream.values],
  from: 'parlance 0.2.0',
  dartName: 'dataWords',
);

typedef DataNumbers = ({int start, int count});

Map<String, Object?> _$DataNumbersTo(DataNumbers p) => {
  'start': p.start,
  'count': p.count,
};

DataNumbers _$DataNumbersFrom(Map<String, Object?> m) =>
    (start: m['start']! as int, count: (m['count'] as int?) ?? 3);

Object? _$DataNumbersAt(DataNumbers p, int i) => switch (i) {
  0 => p.start,
  _ => p.count,
};

Map<String, Object?> _$DataReadingToJson(Reading v) => v.toJson();

typedef DataReadings = ({Reading from});

Map<String, Object?> _$DataReadingsTo(DataReadings p) => {'from': p.from};

DataReadings _$DataReadingsFrom(Map<String, Object?> m) =>
    (from: m['from']! as Reading);

Object? _$DataReadingsAt(DataReadings p, int i) => p.from;
