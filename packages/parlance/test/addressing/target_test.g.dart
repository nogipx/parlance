// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'target_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Counter].
enum CounterState<T> implements IStateWord<T> {
  value<int>('counter.value', PlainShape(IntType())),
  item<int>('counter.item', PlainShape(IntType()), key: 'item'),
  caller<String>('counter.caller', PlainShape(TextType()));

  const CounterState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Counter].
enum CounterCommand<P, R> implements ICommandWord<P, R> {
  add<CounterAdd, int>(
    'counter.add',
    RecordShape<CounterAdd>(
      {'amount': Part(PlainShape(IntType()))},
      to: _$CounterAddTo,
      from: _$CounterAddFrom,
      get: _$CounterAddAt,
    ),
    PlainShape(IntType()),
  );

  const CounterCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The queries of [Counter].
enum CounterQuery<P, R> implements IQueryWord<P, R> {
  current<(), int>('counter.current', RecordShape.none, PlainShape(IntType()));

  const CounterQuery(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R> returns;
}

/// The server streams of [Counter].
enum CounterServerStream<P, T> implements IServerStreamWord<P, T> {
  samples<(), int>('counter.samples', RecordShape.none, PlainShape(IntType()));

  const CounterServerStream(this.name, this.params, this.shape);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<T> shape;
}

/// The client streams of [Counter].
enum CounterClientStream<P, I, T> implements IClientStreamWord<P, I, T> {
  sum<(), int, int>(
    'counter.sum',
    RecordShape.none,
    PlainShape(IntType()),
    PlainShape(IntType()),
  );

  const CounterClientStream(this.name, this.params, this.input, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<I> input;
  @override
  final Shape<T> returns;
}

/// The bidi streams of [Counter].
enum CounterBidiStream<P, I, T> implements IBidiStreamWord<P, I, T> {
  scale<(), int, int>(
    'counter.scale',
    RecordShape.none,
    PlainShape(IntType()),
    PlainShape(IntType()),
  );

  const CounterBidiStream(this.name, this.params, this.input, this.shape);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<I> input;
  @override
  final Shape<T> shape;
}

/// The facts of [Counter].
enum CounterFact<T> implements IFactWord<T> {
  changed<CounterChanged>(
    'counter.changed',
    RecordShape<CounterChanged>(
      {'value': Part(PlainShape(IntType()))},
      to: _$CounterChangedTo,
      from: _$CounterChangedFrom,
      get: _$CounterChangedAt,
    ),
  );

  const CounterFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The owner base of [Counter]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class CounterOwnerBase implements IOwner {
  CounterOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: CounterVocabulary.definition,
    );
  }

  /// counter.value: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<int> value = Single<int>();

  /// counter.item, by item: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<int> item = Keyed<int>();

  /// counter.caller: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<String> caller = Single<String>();

  IFactSayerOf<CounterChanged>? _$changed;

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(value, p.state(CounterState.value).define());
    Keyed.attach(item, p.state(CounterState.item).define());
    Single.attach(caller, p.state(CounterState.caller).define());
    _$changed = p.fact(CounterFact.changed).define();
    p.command(CounterCommand.add).serve((x) => add(amount: x.amount));
    p.query(CounterQuery.current).serve((_) => current());
    p.serverStream(CounterServerStream.samples).serve((_) => samples());
    p.clientStream(CounterClientStream.sum).serve((x, input) => sum(input));
    p.bidiStream(CounterBidiStream.scale).serve((x, input) => scale(input));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(value);
    Keyed.writeAll(item);
    Single.write(caller);
  }

  /// counter.changed: said by `say`.
  late final CounterChangedFact changed = CounterChangedFact._(this);

  /// Serves counter.add.
  Future<int> add({required int amount});

  /// Answers counter.current.
  int current();

  /// Provides counter.samples for one subscription.
  Stream<int> samples();

  /// Provides counter.sum for one subscription.
  Future<int> sum(Stream<int> values);

  /// Provides counter.scale for one subscription.
  Stream<int> scale(Stream<int> values);
}

/// counter.changed, as [CounterOwnerBase] says it.
final class CounterChangedFact {
  CounterChangedFact._(this._base);
  final CounterOwnerBase _base;

  /// Says counter.changed; on behalf of [by], when given.
  /// Said while its owner is not attached, no one hears it.
  void say({required int value, Principal? by}) =>
      _base._$changed?.say((value: value), by: by);
}

/// The words of [Counter] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class ICounterClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory ICounterClient({
    required IParticipant participant,
    required Principal target,
  }) = _$CounterClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ICounterClient.of({
    required IOwner owner,
    required Principal target,
  }) = _$CounterClient._of;

  /// counter.value: its value now, and its changes.
  IStateOf<int> get value;

  /// counter.item, by item: each value, and its changes.
  IKeyedOf<int> get item;

  /// counter.caller: its value now, and its changes.
  IStateOf<String> get caller;

  /// Calls counter.add; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<int> add({required int amount, CancellationToken? cancel});

  /// Asks counter.current; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<int> current({CancellationToken? cancel});

  /// counter.samples: opens on listen; cancellation ends this operation.
  Stream<int> samples({CancellationToken? cancel});

  /// counter.sum: uploads input and returns its result; cancellation ends this operation.
  Future<int> sum(Stream<int> values, {CancellationToken? cancel});

  /// counter.scale: opens on listen; cancellation ends this operation.
  Stream<int> scale(Stream<int> values, {CancellationToken? cancel});

  /// counter.changed: what it says from now on, and its messages.
  IFactOf<CounterChanged> get changed;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Counter] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Counter] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$CounterClient implements ICounterClient {
  _$CounterClient({
    required IParticipant participant,
    required Principal target,
  }) : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      CounterVocabulary.words,
      from: CounterVocabulary.definition.from,
    );
  }

  _$CounterClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      CounterVocabulary.words,
      from: CounterVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IStateOf<int> get value => _$words.stateOf(CounterState.value);

  @override
  IKeyedOf<int> get item => _$words.keyedOf(CounterState.item);

  @override
  IStateOf<String> get caller => _$words.stateOf(CounterState.caller);

  @override
  Future<int> add({required int amount, CancellationToken? cancel}) async {
    final r = await _$words.command(CounterCommand.add).call((
      amount: amount,
    ), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<int> current({CancellationToken? cancel}) async {
    final r = await _$words.query(CounterQuery.current).ask((), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Stream<int> samples({CancellationToken? cancel}) => _$words
      .serverStream(CounterServerStream.samples)
      .open((), cancel: cancel);

  @override
  Future<int> sum(Stream<int> values, {CancellationToken? cancel}) => _$words
      .clientStream(CounterClientStream.sum)
      .call((), values, cancel: cancel);

  @override
  Stream<int> scale(Stream<int> values, {CancellationToken? cancel}) => _$words
      .bidiStream(CounterBidiStream.scale)
      .open((), values, cancel: cancel);

  @override
  IFactOf<CounterChanged> get changed => _$words.factOf(CounterFact.changed);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(CounterVocabulary.words);
}

/// The vocabulary of [Counter], independent of its publishing target.
abstract final class CounterVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'counter';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [
    ...CounterState.values,
    ...CounterCommand.values,
    ...CounterQuery.values,
    ...CounterFact.values,
    ...CounterServerStream.values,
    ...CounterClientStream.values,
    ...CounterBidiStream.values,
  ];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.3.0',
    dartName: 'CounterVocabulary.definition',
  );
}

typedef CounterAdd = ({int amount});

Map<String, Object?> _$CounterAddTo(CounterAdd p) => {'amount': p.amount};

CounterAdd _$CounterAddFrom(Map<String, Object?> m) =>
    (amount: m['amount']! as int);

Object? _$CounterAddAt(CounterAdd p, int i) => p.amount;

typedef CounterChanged = ({int value});

Map<String, Object?> _$CounterChangedTo(CounterChanged p) => {'value': p.value};

CounterChanged _$CounterChangedFrom(Map<String, Object?> m) =>
    (value: m['value']! as int);

Object? _$CounterChangedAt(CounterChanged p, int i) => p.value;

/// The commands of [Bridge].
enum BridgeCommand<P, R> implements ICommandWord<P, R> {
  forward<BridgeForward, int>(
    'bridge.forward',
    RecordShape<BridgeForward>(
      {'amount': Part(PlainShape(IntType()))},
      to: _$BridgeForwardTo,
      from: _$BridgeForwardFrom,
      get: _$BridgeForwardAt,
    ),
    PlainShape(IntType()),
  );

  const BridgeCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The owner base of [Bridge]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class BridgeOwnerBase implements IOwner {
  BridgeOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: BridgeVocabulary.definition,
    );
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    p.command(BridgeCommand.forward).serve((x) => forward(amount: x.amount));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }

  /// Serves bridge.forward.
  Future<int> forward({required int amount});
}

/// The words of [Bridge] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IBridgeClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IBridgeClient({
    required IParticipant participant,
    required Principal target,
  }) = _$BridgeClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IBridgeClient.of({required IOwner owner, required Principal target}) =
      _$BridgeClient._of;

  /// Calls bridge.forward; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<int> forward({required int amount, CancellationToken? cancel});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Bridge] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Bridge] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$BridgeClient implements IBridgeClient {
  _$BridgeClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      BridgeVocabulary.words,
      from: BridgeVocabulary.definition.from,
    );
  }

  _$BridgeClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      BridgeVocabulary.words,
      from: BridgeVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  Future<int> forward({required int amount, CancellationToken? cancel}) async {
    final r = await _$words.command(BridgeCommand.forward).call((
      amount: amount,
    ), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(BridgeVocabulary.words);
}

/// The vocabulary of [Bridge], independent of its publishing target.
abstract final class BridgeVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'bridge';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [...BridgeCommand.values];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance 0.3.0',
    dartName: 'BridgeVocabulary.definition',
  );
}

typedef BridgeForward = ({int amount});

Map<String, Object?> _$BridgeForwardTo(BridgeForward p) => {'amount': p.amount};

BridgeForward _$BridgeForwardFrom(Map<String, Object?> m) =>
    (amount: m['amount']! as int);

Object? _$BridgeForwardAt(BridgeForward p, int i) => p.amount;
