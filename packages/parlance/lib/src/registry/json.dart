/// JSON values: what a registry holds and sends.
///
/// A value is `null`, a `bool`, a `num`, a `String`, a `List` of values or a
/// `Map<String, Object?>` of values. Everything crosses a process boundary
/// and is persisted as is, so no codecs.
library;

/// Whether [v] is a JSON value, all the way down.
bool isJsonValue(Object? v) => switch (v) {
  null || bool() || String() => true,
  num() => v.isFinite,
  List() => v.every(isJsonValue),
  Map() => v.entries.every((e) => e.key is String && isJsonValue(e.value)),
  _ => false,
};

/// A deep, unmodifiable copy of [v], so a value cannot change after it
/// entered the registry.
///
/// Throws [ArgumentError] when [v] is not a JSON value.
Object? freezeJson(Object? v) => switch (v) {
  null || bool() || String() => v,
  num() when v.isFinite => v,
  List() => List<Object?>.unmodifiable(v.map(freezeJson)),
  Map() => Map<String, Object?>.unmodifiable({
    for (final e in v.entries) _stringKey(e.key): freezeJson(e.value),
  }),
  _ => throw ArgumentError.value(v, 'value', 'not a JSON value'),
};

String _stringKey(Object? k) =>
    k is String ? k : throw ArgumentError.value(k, 'key', 'not a string');

/// Deep equality of two JSON values. `1` and `1.0` are equal, as in JSON.
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  return switch ((a, b)) {
    (num x, num y) => x == y,
    (List<Object?> x, List<Object?> y) =>
      x.length == y.length && _every(x.length, (i) => jsonEquals(x[i], y[i])),
    (Map<Object?, Object?> x, Map<Object?, Object?> y) =>
      x.length == y.length &&
          x.entries.every(
            (e) => y.containsKey(e.key) && jsonEquals(e.value, y[e.key]),
          ),
    _ => a == b,
  };
}

bool _every(int n, bool Function(int) f) {
  for (var i = 0; i < n; i++) {
    if (!f(i)) return false;
  }
  return true;
}

/// The value at [path] (dot-separated map keys and list indexes) inside
/// [root], or null when the path leads nowhere.
Object? jsonAt(Object? root, String path) {
  if (path.isEmpty) return root;
  Object? at = root;
  for (final part in path.split('.')) {
    at = switch (at) {
      Map() => at[part],
      List() => switch (int.tryParse(part)) {
        final i? when i >= 0 && i < at.length => at[i],
        _ => null,
      },
      _ => null,
    };
    if (at == null) return null;
  }
  return at;
}

final Expando<int> _weights = Expando('weight');

/// About how many bytes [v] takes as JSON. A value's weight is kept with
/// it, so a value shared by many histories is weighed once.
int jsonWeight(Object? v) =>
    v is List || v is Map ? _weights[v!] ??= _weigh(v) : _weigh(v);

int _weigh(Object? v) {
  switch (v) {
    case String():
      return 16 + v.length;
    case List():
      var n = 16;
      for (var i = 0; i < v.length; i++) {
        n += _weigh(v[i]);
      }
      return n;
    case Map<String, Object?>():
      var n = 16;
      for (final MapEntry(:key, :value) in v.entries) {
        n += 16 + key.length + _weigh(value);
      }
      return n;
    default:
      return 8;
  }
}
