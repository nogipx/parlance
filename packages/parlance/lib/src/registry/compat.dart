import 'descriptors.dart';
import 'json.dart';
import 'words.dart';

// Whether a word is what code was built against (SPEC §23.3, §6.5): one
// rule for a vocabulary's kept schema and for a word met at run time.

/// What [w] says of itself: its kind and its types, as a schema entry.
Map<String, Object?> schemaOfWord(IWord w) => switch (w) {
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

/// What a word defined in the registry says of itself, as a schema entry
/// of [schemaOfWord]'s form.
Map<String, Object?> schemaOfDescriptor(Descriptor d) => switch (d) {
  StateDescriptor(:final type, :final key) => {
    'is': 'state',
    'type': type.toJson(),
    'key': ?key,
  },
  CommandDescriptor(:final params, :final returns) => {
    'is': 'command',
    'params': params.toJson(),
    if (returns != null) 'returns': returns.toJson(),
  },
  QueryDescriptor(:final params, :final returns) => {
    'is': 'query',
    'params': params.toJson(),
    if (returns != null) 'returns': returns.toJson(),
  },
  FactDescriptor(:final type) => {'is': 'fact', 'type': type.toJson()},
};

/// Whether [now] keeps every promise [before] made: the same, or only
/// params added to a command or query that a caller may leave out, so
/// every call made before still passes.
bool keepsPromises(Object? before, Object? now) =>
    jsonEquals(before, now) || _onlyAdds(before, now);

/// Every place [now] differs from [before], each as `path: was …, is …`,
/// in the order the schema says them.
List<String> differences(Object? before, Object? now) {
  final out = <String>[];
  void walk(String at, Object? a, Object? b) {
    if (jsonEquals(a, b)) return;
    if (a is Map && b is Map) {
      for (final k in {...a.keys, ...b.keys}) {
        walk(at.isEmpty ? '$k' : '$at.$k', a[k], b[k]);
      }
      return;
    }
    out.add('${at.isEmpty ? 'it' : at}: was ${_said(a)}, is ${_said(b)}');
  }

  walk('', before, now);
  return out;
}

String _said(Object? v) => v == null ? 'nothing' : '$v';

/// What of [word] the code was built against does [live], the word met,
/// break: empty when it keeps every promise, else every difference but a
/// param added that a caller may leave out, which breaks nothing.
List<String> wordBreaks(IWord word, Descriptor live) {
  final before = schemaOfWord(word);
  final now = schemaOfDescriptor(live);
  if (keepsPromises(before, now)) return const [];
  final added = {
    for (final MapEntry(:key, :value) in _fields(now).entries)
      if (!_fields(before).containsKey(key) &&
          value is Map &&
          value['optional'] == true)
        'params.fields.$key',
  };
  return [
    for (final d in differences(before, now))
      if (!added.any((a) => d.startsWith('$a:'))) d,
  ];
}

/// The params' fields of a command's or query's schema entry.
Map<Object?, Object?> _fields(Object? entry) =>
    ((entry as Map?)?['params'] as Map?)?['fields'] as Map? ?? const {};

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
