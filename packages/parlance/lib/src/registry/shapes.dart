import 'dart:collection';

import 'json.dart';
import 'types.dart';

// Shapes (SPEC §18): how a value of a Dart type is checked, kept and told
// as JSON, to the rule its type holds the JSON to.

/// How a value of the Dart type [T] is checked, kept and told as JSON
/// (checked by [type]) (SPEC §18).
///
/// What it does to a Dart value is what [type] does to its JSON: [check]
/// passes and refuses what [type] passes and refuses, with the same words
/// at the same path, [equals] holds where the JSON is equal, [weigh] is
/// about the JSON's weight. So a value written here and one come as JSON
/// are held to one rule.
abstract base class Shape<T> {
  const Shape();

  ValueType<Object?> get type;
  Object? toJson(T value);
  T fromJson(Object? json);

  /// Whether the registry can keep a value of it as the value itself;
  /// false when only its JSON can be kept, as for a class that serializes
  /// itself ([JsonShape]): what it holds inside is its own.
  bool get keptAsIs => true;

  /// [value] as the registry keeps it: checked as [type] checks its JSON,
  /// its left-out fields given their defaults, and unmodifiable all the
  /// way down, so nobody changes it after it is kept. The same value when
  /// nothing of it had to change. Throws [TypeMismatch] where its JSON
  /// would fail.
  T check(T value, ITypeContext ctx, [String path = '']);

  /// Whether [a] and [b] are one value: whether their JSON is equal.
  bool equals(T a, T b);

  /// About how many bytes its JSON takes, as `jsonWeight` weighs it.
  int weigh(T value);
}

/// The lists and maps the shapes made: unmodifiable, and checked already
/// but for what the registry knows now (entities, the host's types).
final Expando<bool> _kept = Expando('kept');

String _at(String path, String key) => path.isEmpty ? key : '$path.$key';

/// [list] with each item [at] gives, unmodifiable; [list] itself when it
/// is one the shapes made and [at] changed none of it.
List<T> _keepList<T>(List<T> list, T Function(int i) at) {
  var same = _kept[list] == true;
  final out = List<T>.generate(list.length, (i) {
    final v = at(i);
    if (same && !identical(v, list[i])) same = false;
    return v;
  }, growable: false);
  if (same) return list;
  final kept = UnmodifiableListView(out);
  _kept[kept] = true;
  return kept;
}

/// The JSON values of a shape that holds JSON ([Plain] of an object or a
/// list, [JsonValue]): frozen, as the registry has always kept JSON.
Object? _keepJson(Object? v) => v is List || v is Map ? freezeJson(v) : v;

/// A value that is JSON itself: what the registry keeps of a word with no
/// Dart type (a plugin's, a guest's in another language, one named at run
/// time), checked by [type].
final class JsonValue extends Shape<Object?> {
  const JsonValue(this.type);

  @override
  final ValueType<Object?> type;

  @override
  Object? toJson(Object? value) => value;

  @override
  Object? fromJson(Object? json) => json;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) =>
      _keepJson(type.check(value, ctx, path));

  @override
  bool equals(Object? a, Object? b) => jsonEquals(a, b);

  @override
  int weigh(Object? value) => jsonWeight(value);
}

/// A value kept as it is: a bool, an int, a num, a text or an entity id.
/// Its Dart type is its type's: `Plain(BoolType())` is a `Shape<bool>`.
final class Plain<T> extends Shape<T> {
  const Plain(this.type);

  @override
  final ValueType<T> type;

  @override
  Object? toJson(T value) => value;

  @override
  T fromJson(Object? json) => json as T;

  @override
  T check(T value, ITypeContext ctx, [String path = '']) =>
      _keepJson(type.check(value, ctx, path)) as T;

  @override
  bool equals(T a, T b) => jsonEquals(a, b);

  @override
  int weigh(T value) => jsonWeight(value);
}

/// A class that serializes itself, as json_serializable and freezed make
/// them: kept as the map [toJson] gives, read back by [fromJson]. Give its
/// [type] (an `ObjectType` of its fields) for the registry to check what
/// is written and `describe` to tell it; without one any object passes.
///
/// [toJson] must give plain JSON all the way down: with json_serializable,
/// `explicitToJson: true`, or a nested object stays a Dart object and the
/// write is refused.
final class JsonShape<T> extends Shape<T> {
  const JsonShape(this._from, this._to, {ValueType<Object?>? type})
    : _type = type;

  final T Function(Map<String, Object?> json) _from;
  final Map<String, Object?> Function(T value) _to;
  final ValueType<Object?>? _type;

  @override
  ValueType<Object?> get type => _type ?? const AnyType();

  @override
  Object? toJson(T value) {
    final json = _to(value);
    if (!isJsonValue(json)) {
      throw ArgumentError.value(
        value,
        'value',
        'its toJson gives more than JSON: with json_serializable, set '
            'explicitToJson: true',
      );
    }
    return json;
  }

  @override
  T fromJson(Object? json) => _from((json! as Map).cast<String, Object?>());

  /// What it holds inside is its own: kept as its JSON, so [check] goes
  /// through it.
  @override
  bool get keptAsIs => false;

  @override
  T check(T value, ITypeContext ctx, [String path = '']) =>
      fromJson(freezeJson(type.check(toJson(value), ctx, path)));

  @override
  bool equals(T a, T b) => jsonEquals(toJson(a), toJson(b));

  @override
  int weigh(T value) => jsonWeight(toJson(value));
}

/// One of a Dart enum's [values], kept as its name.
final class EnumShape<E extends Enum> extends Shape<E> {
  const EnumShape(this.values);

  final List<E> values;

  @override
  EnumType get type => EnumType([for (final v in values) v.name]);

  @override
  Object? toJson(E value) => value.name;

  @override
  E fromJson(Object? json) => values.byName(json! as String);

  /// One of [values] by its type: nothing to check.
  @override
  E check(E value, ITypeContext ctx, [String path = '']) => value;

  @override
  bool equals(E a, E b) => identical(a, b);

  @override
  int weigh(E value) => 16 + value.name.length;
}

/// A list of [item]s.
final class ListShape<T> extends Shape<List<T>> {
  const ListShape(this.item, {this.maxItems});

  final Shape<T> item;
  final int? maxItems;

  @override
  ListType get type => ListType(item.type, maxItems: maxItems);

  @override
  Object? toJson(List<T> value) => [for (final v in value) item.toJson(v)];

  @override
  List<T> fromJson(Object? json) => List.unmodifiable([
    for (final v in json! as List<Object?>) item.fromJson(v),
  ]);

  @override
  bool get keptAsIs => item.keptAsIs;

  @override
  List<T> check(List<T> value, ITypeContext ctx, [String path = '']) {
    if (maxItems case final m? when value.length > m) {
      throw TypeMismatch(path, 'more than $m items');
    }
    return _keepList(value, (i) => item.check(value[i], ctx, _at(path, '$i')));
  }

  @override
  bool equals(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i]) && !item.equals(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  int weigh(List<T> value) {
    var n = 16;
    for (final v in value) {
      n += item.weigh(v);
    }
    return n;
  }
}

/// [of], or null.
final class Nullable<T> extends Shape<T?> {
  const Nullable(this.of);

  final Shape<T> of;

  @override
  NullableType get type => NullableType(of.type);

  @override
  Object? toJson(T? value) => value == null ? null : of.toJson(value);

  @override
  T? fromJson(Object? json) => json == null ? null : of.fromJson(json);

  @override
  bool get keptAsIs => of.keptAsIs;

  @override
  T? check(T? value, ITypeContext ctx, [String path = '']) =>
      value == null ? null : of.check(value, ctx, path);

  @override
  bool equals(T? a, T? b) =>
      a == null || b == null ? a == null && b == null : of.equals(a, b);

  @override
  int weigh(T? value) => value == null ? 8 : of.weigh(value);
}

/// A map from text to [value]s.
final class MapShape<T> extends Shape<Map<String, T>> {
  const MapShape(this.value, {this.maxEntries});

  final Shape<T> value;
  final int? maxEntries;

  @override
  MapType get type => MapType(value.type, maxEntries: maxEntries);

  @override
  Object? toJson(Map<String, T> v) => {
    for (final e in v.entries) e.key: value.toJson(e.value),
  };

  @override
  Map<String, T> fromJson(Object? json) => Map.unmodifiable({
    for (final e in (json! as Map<Object?, Object?>).entries)
      e.key! as String: value.fromJson(e.value),
  });

  @override
  bool get keptAsIs => value.keptAsIs;

  @override
  Map<String, T> check(Map<String, T> v, ITypeContext ctx, [String path = '']) {
    if (maxEntries case final m? when v.length > m) {
      throw TypeMismatch(path, 'more than $m entries');
    }
    var same = _kept[v] == true;
    final out = <String, T>{};
    for (final MapEntry(:key, value: e) in v.entries) {
      final c = value.check(e, ctx, _at(path, key));
      if (same && !identical(c, e)) same = false;
      out[key] = c;
    }
    if (same) return v;
    final kept = UnmodifiableMapView(out);
    _kept[kept] = true;
    return kept;
  }

  @override
  bool equals(Map<String, T> a, Map<String, T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final MapEntry(:key, value: x) in a.entries) {
      if (!b.containsKey(key)) return false;
      final y = b[key] as T;
      if (!identical(x, y) && !value.equals(x, y)) return false;
    }
    return true;
  }

  @override
  int weigh(Map<String, T> v) {
    var n = 16;
    for (final MapEntry(:key, value: e) in v.entries) {
      n += 16 + key.length + value.weigh(e);
    }
    return n;
  }
}

/// A field of a [RecordShape].
final class Part {
  const Part(
    this.shape, {
    bool optional = false,
    this.defaultValue,
    this.description,
  }) : optional = optional || defaultValue != null;

  /// What it is, for people and agents (a tool's schema says it).
  final String? description;

  final Shape<Object?> shape;

  /// May be left out (its value is then absent); true with a default.
  final bool optional;

  /// What a left-out field becomes, as JSON.
  final Object? defaultValue;
}

/// An object with named [fields], as the Dart type [T] (a record, usually).
///
/// [to] gives a [T]'s fields as Dart values, [from] makes a [T] of them;
/// each field's shape turns its value into JSON and back. Its names are
/// written here, beside the fields, and nowhere else.
final class RecordShape<T> extends Shape<T> {
  const RecordShape(this.fields, {required this.to, required this.from});

  final Map<String, Part> fields;
  final Map<String, Object?> Function(T value) to;
  final T Function(Map<String, Object?> fields) from;

  /// No fields: the params of a command that takes none.
  static const none = RecordShape<()>({}, to: _noFields, from: _unit);

  @override
  ObjectType get type => ObjectType({
    for (final MapEntry(:key, value: p) in fields.entries)
      key: Field(
        p.shape.type,
        optional: p.optional,
        defaultValue: p.defaultValue,
        description: p.description,
      ),
  });

  @override
  Map<String, Object?> toJson(T value) {
    final dart = to(value);
    for (final k in dart.keys) {
      if (!fields.containsKey(k)) throw ArgumentError('no field $k');
    }
    return {
      for (final MapEntry(:key, value: p) in fields.entries)
        // A null a field may be is said: it is a value of its own.
        if (dart[key] != null || (p.shape is Nullable && !p.optional))
          key: p.shape.toJson(dart[key]),
    };
  }

  @override
  T fromJson(Object? json) {
    final m = json! as Map<Object?, Object?>;
    return from({
      for (final MapEntry(:key, value: p) in fields.entries)
        if (m[key] != null) key: p.shape.fromJson(m[key]),
    });
  }

  @override
  bool get keptAsIs => fields.values.every((p) => p.shape.keptAsIs);

  /// Whether field [p] of value [v] is in its JSON: a null is said only of
  /// a field that may be null and is not optional ([toJson]).
  static bool _said(Part p, Object? v) =>
      v != null || (p.shape is Nullable && !p.optional);

  /// Checks each field as `ObjectType` checks it, in the same order, and
  /// gives a left-out one its default; a new record only when a field
  /// changed.
  @override
  T check(T value, ITypeContext ctx, [String path = '']) {
    final dart = to(value);
    for (final k in dart.keys) {
      if (!fields.containsKey(k)) throw ArgumentError('no field $k');
    }
    Map<String, Object?>? changed;
    for (final MapEntry(:key, value: p) in fields.entries) {
      final v = dart[key];
      final at = _at(path, key);
      final Object? c;
      if (_said(p, v)) {
        c = v == null ? null : p.shape.check(v, ctx, at);
      } else if (p.defaultValue != null) {
        final json = p.shape.type.check(p.defaultValue, ctx, at);
        c = p.shape.check(p.shape.fromJson(json), ctx, at);
      } else if (!p.optional) {
        throw TypeMismatch(at, 'missing');
      } else {
        c = null;
      }
      if (!identical(c, v)) (changed ??= Map.of(dart))[key] = c;
    }
    if (changed == null) return value;
    return from({
      for (final MapEntry(:key, :value) in changed.entries) key: ?value,
    });
  }

  @override
  bool equals(T a, T b) {
    if (identical(a, b)) return true;
    final x = to(a);
    final y = to(b);
    for (final MapEntry(:key, value: p) in fields.entries) {
      final u = x[key];
      final v = y[key];
      if (identical(u, v)) continue;
      if (u == null || v == null || !p.shape.equals(u, v)) return false;
    }
    return true;
  }

  @override
  int weigh(T value) {
    final dart = to(value);
    var n = 16;
    for (final MapEntry(:key, value: p) in fields.entries) {
      final v = dart[key];
      if (_said(p, v)) {
        n += 16 + key.length + (v == null ? 8 : p.shape.weigh(v));
      }
    }
    return n;
  }

  static Map<String, Object?> _noFields(() _) => const {};
  static () _unit(Map<String, Object?> _) => ();
}

/// One of several objects as the Dart type [T] (a sealed class, usually),
/// told apart by the text in field [key]: each variant is a [RecordShape]
/// of one subtype, named by its tag. [tagOf] names a value's variant.
final class UnionShape<T> extends Shape<T> {
  const UnionShape(
    this.key,
    this.variants, {
    required this.tagOf,
    this.descriptions = const {},
  });

  final String key;
  final Map<String, RecordShape<T>> variants;
  final String Function(T value) tagOf;

  /// What each variant is for, by its tag (a tool's schema says it).
  final Map<String, String> descriptions;

  @override
  OneOfType get type => OneOfType(key, {
    for (final MapEntry(key: tag, value: v) in variants.entries) tag: v.type,
  }, descriptions: descriptions);

  @override
  Map<String, Object?> toJson(T value) {
    final tag = tagOf(value);
    final v = variants[tag] ?? (throw ArgumentError('no variant $tag'));
    return {key: tag, ...v.toJson(value)};
  }

  @override
  T fromJson(Object? json) {
    final m = json! as Map<Object?, Object?>;
    final v = variants[m[key]] ?? (throw FormatException('$key: ${m[key]}'));
    return v.fromJson({
      for (final e in m.entries)
        if (e.key != key) e.key: e.value,
    });
  }

  @override
  bool get keptAsIs => variants.values.every((v) => v.keptAsIs);

  RecordShape<T> _variant(T value) {
    final tag = tagOf(value);
    return variants[tag] ?? (throw ArgumentError('no variant $tag'));
  }

  @override
  T check(T value, ITypeContext ctx, [String path = '']) =>
      _variant(value).check(value, ctx, path);

  @override
  bool equals(T a, T b) =>
      identical(a, b) || (tagOf(a) == tagOf(b) && _variant(a).equals(a, b));

  /// Its variant's fields, and the tag beside them.
  @override
  int weigh(T value) =>
      _variant(value).weigh(value) + 32 + key.length + tagOf(value).length;
}
