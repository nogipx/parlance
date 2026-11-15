// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clock.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Clock].
enum ClockState<T> implements IStateWord<T> {
  alarm<DateTime>('clock.alarm', DateTimeShape());

  const ClockState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Clock].
enum ClockCommand<P, R> implements ICommandWord<P, R> {
  setAlarm<ClockSetAlarm, void>(
    'clock.set_alarm',
    RecordShape<ClockSetAlarm>(
      {'at': Part(DateTimeShape())},
      to: _$ClockSetAlarmTo,
      from: _$ClockSetAlarmFrom,
      get: _$ClockSetAlarmAt,
    ),
    null,
  );

  const ClockCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The owner base of [Clock]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class ClockOwnerBase implements IOwner {
  ClockOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: ClockVocabulary.definition,
    );
  }

  /// clock.alarm: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<DateTime> alarm = Single<DateTime>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.own(participant);
    Single.attach(alarm, p.state(ClockState.alarm).define());
    p
        .command(ClockCommand.setAlarm)
        .serve((x) => setAlarm(at: x.at), callers: Callers.anyone);
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(alarm);
  }

  /// Serves clock.set_alarm.
  void setAlarm({required DateTime at});
}

/// The words of [Clock] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IClockClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IClockClient({
    required IParticipant participant,
    required Principal target,
  }) = _$ClockClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IClockClient.of({required IOwner owner, required Principal target}) =
      _$ClockClient._of;

  /// clock.alarm: its value now, and its changes.
  IStateOf<DateTime> get alarm;

  /// Calls clock.set_alarm; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> setAlarm({required DateTime at, CancellationToken? cancel});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Clock] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Clock] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$ClockClient implements IClockClient {
  _$ClockClient({required IParticipant participant, required Principal target})
    : _$words = GeneratedWords(participant: participant, target: target) {
    _$words.builtAgainst(
      ClockVocabulary.words,
      from: ClockVocabulary.definition.from,
    );
  }

  _$ClockClient._of({required IOwner owner, required Principal target})
    : _$words = GeneratedWords.of(owner: owner, target: target) {
    _$words.builtAgainst(
      ClockVocabulary.words,
      from: ClockVocabulary.definition.from,
    );
  }

  final GeneratedWords _$words;

  @override
  IStateOf<DateTime> get alarm => _$words.stateOf(ClockState.alarm);

  @override
  Future<void> setAlarm({
    required DateTime at,
    CancellationToken? cancel,
  }) async {
    final r = await _$words.command(ClockCommand.setAlarm).call((
      at: at,
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
      _$words.mismatches(ClockVocabulary.words);
}

/// The vocabulary of [Clock], independent of its publishing target.
abstract final class ClockVocabulary {
  /// Its portable name, for discovery.
  static const String name = 'clock';

  /// Every typed word in this contract, for `schemaOf`.
  static const List<IWord> words = [
    ...ClockState.values,
    ...ClockCommand.values,
  ];

  /// The definition an owner brings or a host grants to a guest.
  static const WordSet definition = WordSet(
    name,
    words,
    from: 'parlance_generator 0.3.0',
    dartName: 'ClockVocabulary.definition',
  );
}

typedef ClockSetAlarm = ({DateTime at});

Map<String, Object?> _$ClockSetAlarmTo(ClockSetAlarm p) => {'at': p.at};

ClockSetAlarm _$ClockSetAlarmFrom(Map<String, Object?> m) =>
    (at: m['at']! as DateTime);

Object? _$ClockSetAlarmAt(ClockSetAlarm p, int i) => p.at;
