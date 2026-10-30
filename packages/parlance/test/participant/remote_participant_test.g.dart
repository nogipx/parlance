// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_participant_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Kittens].
enum KittensState<T> implements IStateWord<T> {
  lamp<bool>('kittens.lamp', PlainShape(BoolType()));

  const KittensState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Kittens].
enum KittensCommand<P, R> implements ICommandWord<P, R> {
  turn<KittensTurn, void>(
    'kittens.turn',
    RecordShape<KittensTurn>(
      {'on': Part(PlainShape(BoolType()))},
      to: _$KittensTurnTo,
      from: _$KittensTurnFrom,
      get: _$KittensTurnAt,
    ),
    null,
  );

  const KittensCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The facts of [Kittens].
enum KittensFact<T> implements IFactWord<T> {
  purred<KittensPurred>(
    'kittens.purred',
    RecordShape<KittensPurred>(
      {'on': Part(PlainShape(BoolType()))},
      to: _$KittensPurredTo,
      from: _$KittensPurredFrom,
      get: _$KittensPurredAt,
    ),
  );

  const KittensFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The owner base of [Kittens]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class KittensOwnerBase implements IOwner {
  KittensOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: kittensWords,
    );
  }

  /// kittens.lamp: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<bool> lamp = Single<bool>();

  IFactSayerOf<KittensPurred>? _$purred;

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Single.attach(lamp, p.state(KittensState.lamp).define());
    _$purred = p.fact(KittensFact.purred).define();
    p
        .command(KittensCommand.turn)
        .serve(
          (x) => turn(on: x.on),
          callers: const Callers({'user': Access.allow}),
        );
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(lamp);
  }

  /// kittens.purred: said by `say`.
  late final KittensPurredFact purred = KittensPurredFact._(this);

  /// Serves kittens.turn.
  void turn({required bool on});
}

/// kittens.purred, as [KittensOwnerBase] says it.
final class KittensPurredFact {
  KittensPurredFact._(this._base);
  final KittensOwnerBase _base;

  /// Says kittens.purred; on behalf of [by], when given.
  /// Said while its owner is not attached, no one hears it.
  void say({required bool on, Principal? by}) =>
      _base._$purred?.say((on: on), by: by);
}

/// The words of [Kittens] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IKittensClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IKittensClient(IParticipant participant) = _$KittensClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IKittensClient.of(IOwner owner) = _$KittensClient._of;

  /// kittens.lamp: its value now, and its changes.
  IStateOf<bool> get lamp;

  /// Calls kittens.turn; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> turn({required bool on, CancellationToken? cancel});

  /// kittens.purred: what it says from now on, and its messages.
  IFactOf<KittensPurred> get purred;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Kittens] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Kittens] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$KittensClient implements IKittensClient {
  _$KittensClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(kittensWords.words, from: kittensWords.from);
  }

  _$KittensClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(kittensWords.words, from: kittensWords.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<bool> get lamp => _$words.stateOf(KittensState.lamp);

  @override
  Future<void> turn({required bool on, CancellationToken? cancel}) async {
    final r = await _$words.command(KittensCommand.turn).call((
      on: on,
    ), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  IFactOf<KittensPurred> get purred => _$words.factOf(KittensFact.purred);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(kittensWords.words);
}

/// The vocabulary of [Kittens]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const kittensWords = WordSet(
  'kittens',
  [...KittensState.values, ...KittensCommand.values, ...KittensFact.values],
  from: 'parlance',
  dartName: 'kittensWords',
);

typedef KittensTurn = ({bool on});

Map<String, Object?> _$KittensTurnTo(KittensTurn p) => {'on': p.on};

KittensTurn _$KittensTurnFrom(Map<String, Object?> m) => (on: m['on']! as bool);

Object? _$KittensTurnAt(KittensTurn p, int i) => p.on;

typedef KittensPurred = ({bool on});

Map<String, Object?> _$KittensPurredTo(KittensPurred p) => {'on': p.on};

KittensPurred _$KittensPurredFrom(Map<String, Object?> m) =>
    (on: m['on']! as bool);

Object? _$KittensPurredAt(KittensPurred p, int i) => p.on;
