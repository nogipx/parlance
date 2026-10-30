// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'owner_tools_more_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The commands of [Dial].
enum DialCommand<P, R> implements ICommandWord<P, R> {
  set<DialSet, void>(
    'dial.set',
    RecordShape<DialSet>(
      {'to': Part(PlainShape(IntType()))},
      to: _$DialSetTo,
      from: _$DialSetFrom,
      get: _$DialSetAt,
    ),
    null,
  );

  const DialCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The owner base of [Dial]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class DialOwnerBase implements IOwner {
  DialOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: dialWords);
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    p
        .command(DialCommand.set)
        .serve(
          (x) => set(to: x.to),
          callers: Callers.anyone,
          whyNot: whyNotSet,
        );
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }

  /// Serves dial.set.
  void set({required int to});

  /// Why dial.set cannot run now; null when it can.
  String? whyNotSet();
}

/// The words of [Dial] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IDialClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IDialClient(IParticipant participant) = _$DialClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IDialClient.of(IOwner owner) = _$DialClient._of;

  /// Calls dial.set; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> set({required int to, CancellationToken? cancel});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Dial] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Dial] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$DialClient implements IDialClient {
  _$DialClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(dialWords.words, from: dialWords.from);
  }

  _$DialClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(dialWords.words, from: dialWords.from);
  }

  final GeneratedWords _$words;

  @override
  Future<void> set({required int to, CancellationToken? cancel}) async {
    final r = await _$words.command(DialCommand.set).call((
      to: to,
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
      _$words.mismatches(dialWords.words);
}

/// The vocabulary of [Dial]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const dialWords = WordSet(
  'dial',
  [...DialCommand.values],
  from: 'parlance',
  dartName: 'dialWords',
);

typedef DialSet = ({int to});

Map<String, Object?> _$DialSetTo(DialSet p) => {'to': p.to};

DialSet _$DialSetFrom(Map<String, Object?> m) => (to: m['to']! as int);

Object? _$DialSetAt(DialSet p, int i) => p.to;

/// The owner base of [Rules]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class RulesOwnerBase implements IOwner {
  RulesOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: rulesWords);
  }

  void _$define(IParticipant participant) {}

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }
}

/// The words of [Rules] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IRulesClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IRulesClient(IParticipant participant) = _$RulesClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IRulesClient.of(IOwner owner) = _$RulesClient._of;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Rules] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Rules] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$RulesClient implements IRulesClient {
  _$RulesClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(rulesWords.words, from: rulesWords.from);
  }

  _$RulesClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(rulesWords.words, from: rulesWords.from);
  }

  final GeneratedWords _$words;

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(rulesWords.words);
}

/// The vocabulary of [Rules]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const rulesWords = WordSet(
  'rules',
  [],
  from: 'parlance',
  dartName: 'rulesWords',
);

/// The facts of [Bell].
enum BellFact<T> implements IFactWord<T> {
  rang<BellRang>(
    'bell.rang',
    RecordShape<BellRang>(
      {'who': Part(PlainShape(TextType()))},
      to: _$BellRangTo,
      from: _$BellRangFrom,
      get: _$BellRangAt,
    ),
  );

  const BellFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The owner base of [Bell]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class BellOwnerBase implements IOwner {
  BellOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: bellWords);
  }

  IFactSayerOf<BellRang>? _$rang;

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    _$rang = p.fact(BellFact.rang).define();
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }

  /// bell.rang: said by `say`.
  late final BellRangFact rang = BellRangFact._(this);
}

/// bell.rang, as [BellOwnerBase] says it.
final class BellRangFact {
  BellRangFact._(this._base);
  final BellOwnerBase _base;

  /// Says bell.rang; on behalf of [by], when given.
  /// Said while its owner is not attached, no one hears it.
  void say({required String who, Principal? by}) =>
      _base._$rang?.say((who: who), by: by);
}

/// The words of [Bell] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IBellClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IBellClient(IParticipant participant) = _$BellClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IBellClient.of(IOwner owner) = _$BellClient._of;

  /// bell.rang: what it says from now on, and its messages.
  IFactOf<BellRang> get rang;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Bell] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Bell] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$BellClient implements IBellClient {
  _$BellClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(bellWords.words, from: bellWords.from);
  }

  _$BellClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(bellWords.words, from: bellWords.from);
  }

  final GeneratedWords _$words;

  @override
  IFactOf<BellRang> get rang => _$words.factOf(BellFact.rang);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(bellWords.words);
}

/// The vocabulary of [Bell]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const bellWords = WordSet(
  'bell',
  [...BellFact.values],
  from: 'parlance',
  dartName: 'bellWords',
);

typedef BellRang = ({String who});

Map<String, Object?> _$BellRangTo(BellRang p) => {'who': p.who};

BellRang _$BellRangFrom(Map<String, Object?> m) => (who: m['who']! as String);

Object? _$BellRangAt(BellRang p, int i) => p.who;

/// The states of [Lamps].
enum LampsState<T> implements IStateWord<T> {
  lit<bool>('lamps.lit', PlainShape(BoolType()), key: 'bulb');

  const LampsState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Lamps].
enum LampsCommand<P, R> implements ICommandWord<P, R> {
  drop<LampsDrop, void>(
    'lamps.drop',
    RecordShape<LampsDrop>(
      {'bulb': Part(PlainShape(ChoiceType('bulb')))},
      to: _$LampsDropTo,
      from: _$LampsDropFrom,
      get: _$LampsDropAt,
    ),
    null,
  );

  const LampsCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The kinds of choices [Lamps] speaks of: what an owner gives by
/// `choices(LampsChoices.bulb, ...)`.
abstract final class LampsChoices {
  static const String bulb = 'bulb';
}

/// The owner base of [Lamps]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class LampsOwnerBase implements IOwner {
  LampsOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: lampsWords);
  }

  /// lamps.lit, by bulb: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<bool> lit = Keyed<bool>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Keyed.attach(lit, p.state(LampsState.lit).define());
    p
        .command(LampsCommand.drop)
        .serve((x) => drop(bulb: x.bulb), callers: Callers.anyone);
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Keyed.writeAll(lit);
  }

  /// Serves lamps.drop.
  void drop({required String bulb});
}

/// The words of [Lamps] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class ILampsClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory ILampsClient(IParticipant participant) = _$LampsClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory ILampsClient.of(IOwner owner) = _$LampsClient._of;

  /// lamps.lit, by bulb: each value, and its changes.
  IKeyedOf<bool> get lit;

  /// Calls lamps.drop; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> drop({required String bulb, CancellationToken? cancel});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Lamps] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Lamps] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$LampsClient implements ILampsClient {
  _$LampsClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(lampsWords.words, from: lampsWords.from);
  }

  _$LampsClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(lampsWords.words, from: lampsWords.from);
  }

  final GeneratedWords _$words;

  @override
  IKeyedOf<bool> get lit => _$words.keyedOf(LampsState.lit);

  @override
  Future<void> drop({required String bulb, CancellationToken? cancel}) async {
    final r = await _$words.command(LampsCommand.drop).call((
      bulb: bulb,
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
      _$words.mismatches(lampsWords.words);
}

/// The vocabulary of [Lamps]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const lampsWords = WordSet(
  'lamps',
  [...LampsState.values, ...LampsCommand.values],
  from: 'parlance',
  dartName: 'lampsWords',
);

typedef LampsDrop = ({String bulb});

Map<String, Object?> _$LampsDropTo(LampsDrop p) => {'bulb': p.bulb};

LampsDrop _$LampsDropFrom(Map<String, Object?> m) =>
    (bulb: m['bulb']! as String);

Object? _$LampsDropAt(LampsDrop p, int i) => p.bulb;
