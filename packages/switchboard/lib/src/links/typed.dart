import '../registry/words.dart';

/// Link definitions from typed words (SPEC §18): steps and conditions as
/// the links' JSON, with the word's name and its types, so a host's own
/// links cannot name a word that is not there or pass it what it does not
/// take. Values that are references (`$trigger.…`) stay raw JSON.
extension CommandSteps<P, R> on CommandWord<P, R> {
  /// The step that calls it with [params]; [orContinue]: a refusal does not
  /// stop the run.
  Map<String, Object?> step(P params, {bool orContinue = false}) => {
    'call': name,
    'params': this.params.toJson(params),
    if (orContinue) 'orContinue': true,
  };
}

extension StateLinks<T> on StateWord<T> {
  /// The condition that it (of [key]) is [value].
  Map<String, Object?> holds(T value, {String? key}) => {
    'state': name,
    'key': ?key,
    'is': shape.toJson(value),
  };
}

extension FlipSteps on StateWord<bool> {
  /// The step that flips it (of [key]); it needs a setter command.
  Map<String, Object?> flip({String? key, bool orContinue = false}) => {
    'flip': name,
    'key': ?key,
    if (orContinue) 'orContinue': true,
  };
}
