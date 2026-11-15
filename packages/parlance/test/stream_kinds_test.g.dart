// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stream_kinds_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The queries of [Transfer].
enum TransferQuery<P, R> implements IQueryWord<P, R> {
  forbidden<(), int>(
    'transfer.forbidden',
    RecordShape.none,
    PlainShape(IntType()),
  );

  const TransferQuery(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R> returns;
}

/// The server streams of [Transfer].
enum TransferServerStream<P, T> implements IServerStreamWord<P, T> {
  count<TransferCount, int>(
    'transfer.count',
    RecordShape<TransferCount>(
      {'length': Part(PlainShape(IntType()), defaultValue: 5)},
      to: _$TransferCountTo,
      from: _$TransferCountFrom,
      get: _$TransferCountAt,
    ),
    PlainShape(IntType()),
  );

  const TransferServerStream(this.name, this.params, this.shape);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<T> shape;
}

/// The client streams of [Transfer].
enum TransferClientStream<P, I, T> implements IClientStreamWord<P, I, T> {
  sum<TransferSum, int, int>(
    'transfer.sum',
    RecordShape<TransferSum>(
      {'initial': Part(PlainShape(IntType()), defaultValue: 0)},
      to: _$TransferSumTo,
      from: _$TransferSumFrom,
      get: _$TransferSumAt,
    ),
    PlainShape(IntType()),
    PlainShape(IntType()),
  ),
  private<(), int, int>(
    'transfer.private',
    RecordShape.none,
    PlainShape(IntType()),
    PlainShape(IntType()),
  ),
  consume<(), int, void>(
    'transfer.consume',
    RecordShape.none,
    PlainShape(IntType()),
    PlainShape(NullableType(AnyType())),
  );

  const TransferClientStream(this.name, this.params, this.input, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<I> input;
  @override
  final Shape<T> returns;
}

/// The bidi streams of [Transfer].
enum TransferBidiStream<P, I, T> implements IBidiStreamWord<P, I, T> {
  doubleValues<TransferDoubleValues, int, int>(
    'transfer.double',
    RecordShape<TransferDoubleValues>(
      {'factor': Part(PlainShape(IntType()), defaultValue: 2)},
      to: _$TransferDoubleValuesTo,
      from: _$TransferDoubleValuesFrom,
      get: _$TransferDoubleValuesAt,
    ),
    PlainShape(IntType()),
    PlainShape(IntType()),
  );

  const TransferBidiStream(this.name, this.params, this.input, this.shape);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<I> input;
  @override
  final Shape<T> shape;
}

/// The owner base of [Transfer]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class TransferOwnerBase implements IOwner {
  TransferOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: TransferVocabulary.definition,
    );
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    p.query(TransferQuery.forbidden).serve((_) => forbidden());
    p
        .clientStream(TransferClientStream.sum)
        .serve(
          (x, input) => sum(input, initial: x.initial),
          callers: Callers.anyone,
          whyNot: whyNotSum,
        );
    p
        .bidiStream(TransferBidiStream.doubleValues)
        .serve(
          (x, input) => doubleValues(input, factor: x.factor),
          callers: Callers.anyone,
        );
    p
        .clientStream(TransferClientStream.private)
        .serve(
          (x, input) => private(input),
          callers: const Callers({'admin': Access.allow}),
        );
    p
        .clientStream(TransferClientStream.consume)
        .serve((x, input) => consume(input), callers: Callers.anyone);
    p
        .serverStream(TransferServerStream.count)
        .serve((x) => count(length: x.length));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }

  /// Answers transfer.forbidden.
  Future<int> forbidden();

  /// Provides transfer.sum for one subscription.
  Future<int> sum(Stream<int> values, {int initial = 0});

  /// Why a subscription cannot open now; null when ready.
  String? whyNotSum();

  /// Provides transfer.double for one subscription.
  Stream<int> doubleValues(Stream<int> values, {int factor = 2});

  /// Provides transfer.private for one subscription.
  Future<int> private(Stream<int> values);

  /// Provides transfer.consume for one subscription.
  Future<void> consume(Stream<int> values);

  /// Provides transfer.count for one subscription.
  Stream<int> count({int length = 5});
}

/// The words of [Transfer] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class ITransferClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory ITransferClient({
    required IParticipant participant,
    required Principal target,
  }) = _$TransferClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ITransferClient.of({
    required IOwner owner,
    required Principal target,
  }) = _$TransferClient._of;

  /// Asks transfer.forbidden; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<int> forbidden({CancellationToken? cancel});

  /// transfer.sum: uploads input and returns its result; cancellation ends this operation.
  Future<int> sum(
    Stream<int> values, {
    int initial = 0,
    CancellationToken? cancel,
  });

  /// transfer.double: opens on listen; cancellation ends this operation.
  Stream<int> doubleValues(
    Stream<int> values, {
    int factor = 2,
    CancellationToken? cancel,
  });

  /// transfer.private: uploads input and returns its result; cancellation ends this operation.
  Future<int> private(Stream<int> values, {CancellationToken? cancel});

  /// transfer.consume: uploads input and returns its result; cancellation ends this operation.
  Future<void> consume(Stream<int> values, {CancellationToken? cancel});

  /// transfer.count: opens on listen; cancellation ends this operation.
  Stream<int> count({int length = 5, CancellationToken? cancel});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Transfer] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Transfer] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$TransferClient implements ITransferClient {
  _$TransferClient({
    required IParticipant participant,
    required Principal target,
  }) : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      TransferVocabulary.words,
      from: TransferVocabulary.definition.from,
    );
  }

  _$TransferClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      TransferVocabulary.words,
      from: TransferVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  Future<int> forbidden({CancellationToken? cancel}) async {
    final r = await _$words
        .query(TransferQuery.forbidden)
        .ask((), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<int> sum(
    Stream<int> values, {
    int initial = 0,
    CancellationToken? cancel,
  }) => _$words
      .clientStream(TransferClientStream.sum)
      .call((initial: initial), values, cancel: cancel);

  @override
  Stream<int> doubleValues(
    Stream<int> values, {
    int factor = 2,
    CancellationToken? cancel,
  }) => _$words
      .bidiStream(TransferBidiStream.doubleValues)
      .open((factor: factor), values, cancel: cancel);

  @override
  Future<int> private(Stream<int> values, {CancellationToken? cancel}) =>
      _$words
          .clientStream(TransferClientStream.private)
          .call((), values, cancel: cancel);

  @override
  Future<void> consume(Stream<int> values, {CancellationToken? cancel}) =>
      _$words
          .clientStream(TransferClientStream.consume)
          .call((), values, cancel: cancel);

  @override
  Stream<int> count({int length = 5, CancellationToken? cancel}) => _$words
      .serverStream(TransferServerStream.count)
      .open((length: length), cancel: cancel);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(TransferVocabulary.words);
}

/// The vocabulary of [Transfer], independent of its publishing target.
abstract final class TransferVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'transfer';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [
    ...TransferQuery.values,
    ...TransferServerStream.values,
    ...TransferClientStream.values,
    ...TransferBidiStream.values,
  ];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.4.0',
    dartName: 'TransferVocabulary.definition',
  );
}

typedef TransferSum = ({int initial});

Map<String, Object?> _$TransferSumTo(TransferSum p) => {'initial': p.initial};

TransferSum _$TransferSumFrom(Map<String, Object?> m) =>
    (initial: (m['initial'] as int?) ?? 0);

Object? _$TransferSumAt(TransferSum p, int i) => p.initial;

typedef TransferDoubleValues = ({int factor});

Map<String, Object?> _$TransferDoubleValuesTo(TransferDoubleValues p) => {
  'factor': p.factor,
};

TransferDoubleValues _$TransferDoubleValuesFrom(Map<String, Object?> m) =>
    (factor: (m['factor'] as int?) ?? 2);

Object? _$TransferDoubleValuesAt(TransferDoubleValues p, int i) => p.factor;

typedef TransferCount = ({int length});

Map<String, Object?> _$TransferCountTo(TransferCount p) => {'length': p.length};

TransferCount _$TransferCountFrom(Map<String, Object?> m) =>
    (length: (m['length'] as int?) ?? 5);

Object? _$TransferCountAt(TransferCount p, int i) => p.length;
