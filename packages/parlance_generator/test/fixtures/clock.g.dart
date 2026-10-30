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
    IOwner.made(this, define: _$define, write: _$write, vocabulary: clockWords);
  }

  /// clock.alarm: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<DateTime> alarm = Single<DateTime>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
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
  factory IClockClient(IParticipant participant) = _$ClockClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IClockClient.of(IOwner owner) = _$ClockClient._of;

  /// clock.alarm: its value now, and its changes.
  IStateOf<DateTime> get alarm;

  /// Calls clock.set_alarm; a call not done throws [CallNotDone].
  Future<void> setAlarm({required DateTime at});

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
  _$ClockClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(clockWords.words, from: clockWords.from);
  }

  _$ClockClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(clockWords.words, from: clockWords.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<DateTime> get alarm => _$words.stateOf(ClockState.alarm);

  @override
  Future<void> setAlarm({required DateTime at}) async {
    final r = await _$words.command(ClockCommand.setAlarm).call((at: at));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(clockWords.words);
}

/// The vocabulary of [Clock]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const clockWords = WordSet(
  'clock',
  [...ClockState.values, ...ClockCommand.values],
  from: 'parlance_generator',
  dartName: 'clockWords',
);

typedef ClockSetAlarm = ({DateTime at});

Map<String, Object?> _$ClockSetAlarmTo(ClockSetAlarm p) => {'at': p.at};

ClockSetAlarm _$ClockSetAlarmFrom(Map<String, Object?> m) =>
    (at: m['at']! as DateTime);

Object? _$ClockSetAlarmAt(ClockSetAlarm p, int i) => p.at;
