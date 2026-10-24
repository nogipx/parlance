import '../registry/json.dart';
import '../registry/registry.dart';
import 'model.dart';

/// Reads a state value (of a key); null when there is none.
typedef StateReader = Object? Function(String state, String? key);

/// Whether [c] holds on the committed state of [r] now (SPEC §13.3).
bool evaluate(Condition c, Registry r) =>
    evaluateWith(c, (s, k) => r.read(s, key: k));

/// Whether [c] holds on the state [read] gives: the engine's view at the
/// position of the message being handled.
bool evaluateWith(Condition c, StateReader read) => switch (c) {
  StateIs(:final state, :final key, :final test) => test.matches(
    read(state, key),
  ),
  AllOf(:final all) => all.every((x) => evaluateWith(x, read)),
  AnyOf(:final any) => any.any((x) => evaluateWith(x, read)),
};

final RegExp _stateRef = RegExp(r'^\$state\.([a-z0-9_.-]+?)(?:\[([^\]]+)\])?$');
final RegExp _template = RegExp(r'\{\{|\}\}|\{([^{}]+)\}');

/// [value] with references and templates filled (SPEC §13.4):
///
/// - `$trigger` and `$trigger.<path>` — the trigger's data, or a part;
/// - `$state.<name>` and `$state.<name>[<key>]` — a committed value;
/// - `{path}` and `{$state.<name>}` inside text — the same, as text;
///   `{{` and `}}` are literal braces.
Object? resolve(Object? value, Object? trigger, Registry r) => switch (value) {
  final String s => _resolveText(s, trigger, r),
  final List<Object?> l => [for (final x in l) resolve(x, trigger, r)],
  final Map<Object?, Object?> m => {
    for (final e in m.entries) e.key as String: resolve(e.value, trigger, r),
  },
  _ => value,
};

Object? _resolveText(String s, Object? trigger, Registry r) {
  if (s == r'$trigger') return trigger;
  if (s.startsWith(r'$trigger.')) return jsonAt(trigger, s.substring(9));
  if (_stateRef.firstMatch(s) case final m?) {
    return r.read(m[1]!, key: m[2]);
  }
  if (!s.contains('{') && !s.contains('}')) return s;
  return s.replaceAllMapped(_template, (m) {
    final whole = m[0]!;
    if (whole == '{{') return '{';
    if (whole == '}}') return '}';
    final path = m[1]!.trim();
    final v = path.startsWith(r'$')
        ? _resolveText(path, trigger, r)
        : jsonAt(trigger, path);
    return v == null ? '' : '$v';
  });
}

/// The `$state` names [value] reads.
Set<String> stateRefs(Object? value) => switch (value) {
  final String s => {
    if (_stateRef.firstMatch(s) case final m?) m[1]!,
    for (final t in _template.allMatches(s))
      if (t[1] case final p? when _stateRef.hasMatch(p.trim()))
        _stateRef.firstMatch(p.trim())![1]!,
  },
  final List<Object?> l => {for (final x in l) ...stateRefs(x)},
  final Map<Object?, Object?> m => {for (final x in m.values) ...stateRefs(x)},
  _ => const {},
};
