// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'where_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Deck].
enum DeckState<T> implements IStateWord<T> {
  volume<int>('deck.volume', PlainShape(IntType(min: 0, max: 10))),
  level<int>('deck.level', PlainShape(IntType()), key: 'channel');

  const DeckState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Deck].
enum DeckCommand<P, R> implements ICommandWord<P, R> {
  turn<DeckTurn, int>(
    'deck.turn',
    RecordShape<DeckTurn>(
      {'to': Part(PlainShape(IntType(min: 0, max: 10)))},
      to: _$DeckTurnTo,
      from: _$DeckTurnFrom,
      get: _$DeckTurnAt,
    ),
    PlainShape(IntType()),
  ),
  play<DeckPlay, String>(
    'deck.play',
    RecordShape<DeckPlay>(
      {'track': Part(PlainShape(TextType()))},
      to: _$DeckPlayTo,
      from: _$DeckPlayFrom,
      get: _$DeckPlayAt,
    ),
    PlainShape(TextType()),
  ),
  slow<(), void>('deck.slow', RecordShape.none, null),
  late<(), void>('deck.late', RecordShape.none, null),
  fail<(), void>('deck.fail', RecordShape.none, null),
  bump<(), void>('deck.bump', RecordShape.none, null),
  ring<DeckRing, void>(
    'deck.ring',
    RecordShape<DeckRing>(
      {'id': Part(PlainShape(TextType()))},
      to: _$DeckRingTo,
      from: _$DeckRingFrom,
      get: _$DeckRingAt,
    ),
    null,
  );

  const DeckCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The queries of [Deck].
enum DeckQuery<P, R> implements IQueryWord<P, R> {
  find<DeckFind, String>(
    'deck.find',
    RecordShape<DeckFind>(
      {'text': Part(PlainShape(TextType()))},
      to: _$DeckFindTo,
      from: _$DeckFindFrom,
      get: _$DeckFindAt,
    ),
    PlainShape(TextType()),
  );

  const DeckQuery(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R> returns;
}

/// The facts of [Deck].
enum DeckFact<T> implements IFactWord<T> {
  played<DeckPlayed>(
    'deck.played',
    RecordShape<DeckPlayed>(
      {'track': Part(PlainShape(TextType()))},
      to: _$DeckPlayedTo,
      from: _$DeckPlayedFrom,
      get: _$DeckPlayedAt,
    ),
  );

  const DeckFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The kinds of choices [Deck] speaks of: what an owner gives by
/// `choices(DeckChoices.channel, ...)`.
abstract final class DeckChoices {
  static const String channel = 'channel';
}

/// The owner base of [Deck]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class DeckOwnerBase implements IOwner {
  DeckOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: deckWords);
  }

  /// deck.volume: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<int> volume = Single<int>();

  /// deck.level, by channel: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<int> level = Keyed<int>();

  IFactSayerOf<DeckPlayed>? _$played;

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Single.attach(volume, p.state(DeckState.volume).define());
    Keyed.attach(level, p.state(DeckState.level).define());
    _$played = p.fact(DeckFact.played).define();
    p
        .command(DeckCommand.turn)
        .serve((x) => turn(to: x.to), callers: Callers.anyone);
    p
        .command(DeckCommand.play)
        .serve((x) => play(track: x.track), callers: Callers.anyone);
    p.command(DeckCommand.slow).serve((_) => slow(), callers: Callers.anyone);
    p
        .command(DeckCommand.late)
        .serve(
          (_) => late(),
          callers: Callers.anyone,
          deadline: const Duration(microseconds: 50000),
        );
    p.command(DeckCommand.fail).serve((_) => fail(), callers: Callers.anyone);
    p.command(DeckCommand.bump).serve((_) => bump(), callers: Callers.anyone);
    p
        .command(DeckCommand.ring)
        .serve((x) => ring(id: x.id), callers: Callers.anyone);
    p
        .query(DeckQuery.find)
        .serve((x) => find(text: x.text), askers: Callers.anyone);
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(volume);
    Keyed.writeAll(level);
  }

  /// deck.played: said by `say`.
  late final DeckPlayedFact played = DeckPlayedFact._(this);

  /// Serves deck.turn.
  int turn({required int to});

  /// Serves deck.play.
  String play({required String track});

  /// Serves deck.slow.
  Future<void> slow();

  /// Serves deck.late.
  Future<void> late();

  /// Serves deck.fail.
  void fail();

  /// Serves deck.bump.
  void bump();

  /// Serves deck.ring.
  void ring({required String id});

  /// Answers deck.find.
  String find({required String text});
}

/// deck.played, as [DeckOwnerBase] says it.
final class DeckPlayedFact {
  DeckPlayedFact._(this._base);
  final DeckOwnerBase _base;

  /// Says deck.played; on behalf of [by], when given.
  /// Said while its owner is not attached, no one hears it.
  void say({required String track, Principal? by}) =>
      _base._$played?.say((track: track), by: by);
}

/// The words of [Deck] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IDeckClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IDeckClient(IParticipant participant) = _$DeckClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IDeckClient.of(IOwner owner) = _$DeckClient._of;

  /// deck.volume: its value now, and its changes.
  IStateOf<int> get volume;

  /// deck.level, by channel: each value, and its changes.
  IKeyedOf<int> get level;

  /// Calls deck.turn; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<int> turn({required int to, CancellationToken? cancel});

  /// Calls deck.play; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<String> play({required String track, CancellationToken? cancel});

  /// Calls deck.slow; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> slow({CancellationToken? cancel});

  /// Calls deck.late; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> late({CancellationToken? cancel});

  /// Calls deck.fail; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> fail({CancellationToken? cancel});

  /// Calls deck.bump; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> bump({CancellationToken? cancel});

  /// Calls deck.ring; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> ring({required String id, CancellationToken? cancel});

  /// Asks deck.find; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<String> find({required String text, CancellationToken? cancel});

  /// deck.played: what it says from now on, and its messages.
  IFactOf<DeckPlayed> get played;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Deck] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Deck] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$DeckClient implements IDeckClient {
  _$DeckClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(deckWords.words, from: deckWords.from);
  }

  _$DeckClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(deckWords.words, from: deckWords.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<int> get volume => _$words.stateOf(DeckState.volume);

  @override
  IKeyedOf<int> get level => _$words.keyedOf(DeckState.level);

  @override
  Future<int> turn({required int to, CancellationToken? cancel}) async {
    final r = await _$words.command(DeckCommand.turn).call((
      to: to,
    ), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<String> play({
    required String track,
    CancellationToken? cancel,
  }) async {
    final r = await _$words.command(DeckCommand.play).call((
      track: track,
    ), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> slow({CancellationToken? cancel}) async {
    final r = await _$words.command(DeckCommand.slow).call((), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> late({CancellationToken? cancel}) async {
    final r = await _$words.command(DeckCommand.late).call((), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> fail({CancellationToken? cancel}) async {
    final r = await _$words.command(DeckCommand.fail).call((), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> bump({CancellationToken? cancel}) async {
    final r = await _$words.command(DeckCommand.bump).call((), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> ring({required String id, CancellationToken? cancel}) async {
    final r = await _$words.command(DeckCommand.ring).call((
      id: id,
    ), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<String> find({required String text, CancellationToken? cancel}) async {
    final r = await _$words.query(DeckQuery.find).ask((
      text: text,
    ), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  IFactOf<DeckPlayed> get played => _$words.factOf(DeckFact.played);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(deckWords.words);
}

/// The vocabulary of [Deck]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const deckWords = WordSet(
  'deck',
  [
    ...DeckState.values,
    ...DeckCommand.values,
    ...DeckQuery.values,
    ...DeckFact.values,
  ],
  from: 'parlance',
  dartName: 'deckWords',
);

typedef DeckTurn = ({int to});

Map<String, Object?> _$DeckTurnTo(DeckTurn p) => {'to': p.to};

DeckTurn _$DeckTurnFrom(Map<String, Object?> m) => (to: m['to']! as int);

Object? _$DeckTurnAt(DeckTurn p, int i) => p.to;

typedef DeckPlay = ({String track});

Map<String, Object?> _$DeckPlayTo(DeckPlay p) => {'track': p.track};

DeckPlay _$DeckPlayFrom(Map<String, Object?> m) =>
    (track: m['track']! as String);

Object? _$DeckPlayAt(DeckPlay p, int i) => p.track;

typedef DeckRing = ({String id});

Map<String, Object?> _$DeckRingTo(DeckRing p) => {'id': p.id};

DeckRing _$DeckRingFrom(Map<String, Object?> m) => (id: m['id']! as String);

Object? _$DeckRingAt(DeckRing p, int i) => p.id;

typedef DeckFind = ({String text});

Map<String, Object?> _$DeckFindTo(DeckFind p) => {'text': p.text};

DeckFind _$DeckFindFrom(Map<String, Object?> m) => (text: m['text']! as String);

Object? _$DeckFindAt(DeckFind p, int i) => p.text;

typedef DeckPlayed = ({String track});

Map<String, Object?> _$DeckPlayedTo(DeckPlayed p) => {'track': p.track};

DeckPlayed _$DeckPlayedFrom(Map<String, Object?> m) =>
    (track: m['track']! as String);

Object? _$DeckPlayedAt(DeckPlayed p, int i) => p.track;
