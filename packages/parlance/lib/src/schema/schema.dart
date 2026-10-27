import '../registry/json.dart';
import '../registry/words.dart';

/// What [words] say of themselves, by name: each word's kind and its types
/// (SPEC §23.3). A module keeps it beside its words and compares the next
/// with it ([schemaBreaks]), so a published word does not change by
/// accident.
Map<String, Object?> schemaOf(Iterable<IWord> words) => {
  for (final w in words) w.name: _describe(w),
};

Map<String, Object?> _describe(IWord w) => switch (w) {
  IStateWord(:final shape, :final key) => {
    'is': 'state',
    'type': shape.type.toJson(),
    'key': ?key,
  },
  ICommandWord(:final params, :final returns) => {
    'is': 'command',
    'params': params.type.toJson(),
    if (returns != null) 'returns': returns.type.toJson(),
  },
  IQueryWord(:final params, :final returns) => {
    'is': 'query',
    'params': params.type.toJson(),
    'returns': returns.type.toJson(),
  },
  IFactWord(:final shape) => {'is': 'fact', 'type': shape.type.toJson()},
  _ => throw ArgumentError('${w.name} is no word of a kind parlance knows'),
};

/// What changed of the words in [before] that [now] does not say the same:
/// a word gone, or its kind or types changed. A word added is no break,
/// nor a param a command or query takes now that a caller may leave out
/// (optional, or with a default): every call made before still passes.
/// Empty when nothing published changed; otherwise a new version of the
/// word keeps the old one (SPEC §1), or the change is accepted on purpose
/// by keeping [now] as the new baseline.
List<String> schemaBreaks(
  Map<String, Object?> before,
  Map<String, Object?> now,
) => [
  for (final MapEntry(:key, :value) in before.entries)
    if (!now.containsKey(key))
      '$key is gone'
    else if (!jsonEquals(value, now[key]) && !_onlyAdds(value, now[key]))
      '$key changed',
];

/// Whether [now] is [before] with only params added that may be left out.
bool _onlyAdds(Object? before, Object? now) {
  if (before is! Map || now is! Map) return false;
  if (before['is'] != now['is']) return false;
  if (before['is'] != 'command' && before['is'] != 'query') return false;
  // All but the params said the same.
  for (final k in {...before.keys, ...now.keys}) {
    if (k != 'params' && !jsonEquals(before[k], now[k])) return false;
  }
  final was = (before['params'] as Map?)?['fields'] as Map? ?? const {};
  final is_ = (now['params'] as Map?)?['fields'] as Map? ?? const {};
  for (final MapEntry(:key, :value) in was.entries) {
    if (!jsonEquals(value, is_[key])) return false;
  }
  for (final MapEntry(:key, :value) in is_.entries) {
    if (was.containsKey(key)) continue;
    if (value is! Map || value['optional'] != true) return false;
  }
  return true;
}
