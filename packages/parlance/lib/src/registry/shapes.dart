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
  /// would fail, at the same path.
  ///
  /// [was] is the value kept before in its place: a part of [value] that
  /// is the same part of it is kept already, and when its check asks
  /// nothing of the registry ([checkedAlone]) it passes again as it is,
  /// unvisited. So a list of a thousand with one item new costs one item.
  T check(T value, ITypeContext ctx, {T? was});

  /// Whether a value of it is checked by itself alone, asking no entity
  /// and no host's type: a value kept once passes again as it is.
  bool get checkedAlone => _aloneOf[this] ??= _alone(type);

  /// Whether [a] and [b] are one value: whether their JSON is equal.
  bool equals(T a, T b);

  /// About how many bytes its JSON takes, as `jsonWeight` weighs it.
  int weigh(T value);
}

/// The lists and maps the shapes made: unmodifiable, and checked already
/// but for what the registry knows now (entities, the host's types).
final Expando<bool> _kept = Expando('kept');

/// The fields of each record shape in order, read once a shape.
final Expando<List<(String, Part)>> _partsOf = Expando('parts');

/// The weight of each list and map the shapes made, weighed once.
final Expando<int> _weights = Expando('weight');

/// Whether each shape is checked alone, found once a shape.
final Expando<bool> _aloneOf = Expando('alone');

/// Whether a value of [t] is checked asking nothing of the registry.
bool _alone(ValueType<Object?> t) => switch (t) {
  ChoiceType() || CustomType() => false,
  ListType(:final item) => _alone(item),
  MapType(:final value) => _alone(value),
  NullableType(:final of) => _alone(of),
  RecordType(:final fields) => fields.values.every((f) => _alone(f.type)),
  UnionType(:final variants) => variants.values.every(_alone),
  _ => true,
};

/// [e], refused at its path within [at], refused at their path together.
/// A part is checked at its own root and its refusal told where it is on
/// the way out, so no path is made of a value that passes.
TypeMismatch _within(String at, TypeMismatch e) =>
    TypeMismatch(e.path.isEmpty ? at : '$at.${e.path}', e.message);

/// The JSON values of a shape that holds JSON ([PlainShape] of an object or a
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
  Object? check(Object? value, ITypeContext ctx, {Object? was}) =>
      was != null && identical(value, was) && checkedAlone
      ? value
      : _keepJson(type.check(value, ctx));

  @override
  bool equals(Object? a, Object? b) => jsonEquals(a, b);

  @override
  int weigh(Object? value) => jsonWeight(value);
}

/// A value kept as it is: a bool, an int, a num, a text or an entity id.
/// Its Dart type is its type's: `PlainShape(BoolType())` is a `Shape<bool>`.
final class PlainShape<T> extends Shape<T> {
  const PlainShape(this.type);

  @override
  final ValueType<T> type;

  @override
  Object? toJson(T value) => value;

  @override
  T fromJson(Object? json) => json as T;

  /// One equal to the value kept before is that one: what holds it
  /// passes as the same, and an equality asked of it is answered at once.
  @override
  T check(T value, ITypeContext ctx, {T? was}) {
    if (was != null && identical(value, was) && checkedAlone) return value;
    final c = _keepJson(type.check(value, ctx)) as T;
    return was != null && c == was ? was : c;
  }

  @override
  bool equals(T a, T b) => jsonEquals(a, b);

  @override
  int weigh(T value) => jsonWeight(value);
}

/// A class that serializes itself, as json_serializable and freezed make
/// them: kept as the map [toJson] gives, read back by [fromJson]. Give its
/// [type] (a `RecordType` of its fields) for the registry to check what
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
  T check(T value, ITypeContext ctx, {T? was}) =>
      fromJson(freezeJson(type.check(toJson(value), ctx)));

  @override
  bool equals(T a, T b) => jsonEquals(toJson(a), toJson(b));

  @override
  int weigh(T value) => jsonWeight(toJson(value));
}

/// A value code reads that its shape does not know and has no fallback
/// for (SPEC §25.2): an enum value or a variant added after the code was
/// built. A typed read gives none rather than throw it.
final class UnknownValue implements Exception {
  const UnknownValue(this.value, this.known);

  final String value;

  /// What the code knows there.
  final List<String> known;

  @override
  String toString() =>
      '$value is not one of ${known.join(', ')}, the values this code knows';
}

/// One of a Dart enum's [values], kept as its name. A name it does not
/// know reads as [unknown] (SPEC §25.2); with none, it is an
/// [UnknownValue].
final class EnumShape<E extends Enum> extends Shape<E> {
  const EnumShape(this.values, {this.unknown});

  final List<E> values;

  /// What a value added after the code was built reads as: one of
  /// [values], kept for it (`other`).
  final E? unknown;

  @override
  EnumType get type =>
      EnumType([for (final v in values) v.name], unknown: unknown?.name);

  @override
  Object? toJson(E value) => value.name;

  @override
  E fromJson(Object? json) {
    final name = json! as String;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return unknown ??
        (throw UnknownValue(name, [for (final v in values) v.name]));
  }

  /// One of [values] by its type: nothing to check.
  @override
  E check(E value, ITypeContext ctx, {E? was}) => value;

  @override
  bool equals(E a, E b) => identical(a, b);

  @override
  int weigh(E value) => 16 + value.name.length;
}

/// A Dart [Duration], kept as its whole milliseconds (SPEC §2), at most
/// [max].
final class DurationShape extends Shape<Duration> {
  const DurationShape({this.max});

  /// The longest it may be.
  final Duration? max;

  @override
  DurationType get type => DurationType(max: max?.inMilliseconds);

  @override
  Object? toJson(Duration value) => value.inMilliseconds;

  @override
  Duration fromJson(Object? json) => Duration(milliseconds: json! as int);

  @override
  Duration check(Duration value, ITypeContext ctx, {Duration? was}) {
    type.check(value.inMilliseconds, ctx);
    return value;
  }

  @override
  bool equals(Duration a, Duration b) => a == b;

  @override
  int weigh(Duration value) => 8;
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

  /// An item the same as the one kept in its place before, when items are
  /// checked alone, passes unvisited; the weight is the one before, told
  /// what changed.
  @override
  List<T> check(List<T> value, ITypeContext ctx, {List<T>? was}) {
    if (maxItems case final m? when value.length > m) {
      throw TypeMismatch('', 'more than $m items');
    }
    // One the shapes made is checked already, all of it.
    if (_kept[value] == true && item.checkedAlone) return value;
    final before = was != null && _kept[was] == true && item.checkedAlone
        ? was
        : null;
    var weight = before == null ? null : _weights[before];
    var same = _kept[value] == true;
    // Whether every item is the one kept in its place before: then the
    // list is that one, and nothing new is made.
    var asBefore = before != null && before.length == value.length;
    // Copied only once an item checked is another than it was.
    List<T>? out;
    var i = 0;
    try {
      for (; i < value.length; i++) {
        final v = value[i];
        final had = before != null && i < before.length;
        if (had && identical(v, before[i])) continue;
        final c = item.check(v, ctx, was: had ? before[i] : null);
        final kept = had && identical(c, before[i]);
        if (asBefore && !kept) asBefore = false;
        if (!identical(c, v)) {
          (out ??= List<T>.of(value, growable: false))[i] = c;
          same = false;
        }
        if (weight != null && !kept) {
          weight += item.weigh(c) - (had ? item.weigh(before[i]) : 0);
        }
      }
    } on TypeMismatch catch (e) {
      throw _within('$i', e);
    }
    if (weight != null) {
      var w = weight;
      for (var j = value.length; j < before!.length; j++) {
        w -= item.weigh(before[j]);
      }
      weight = w;
    }
    if (asBefore) return before!;
    if (same) return value;
    final kept = UnmodifiableListView(
      out ?? List<T>.of(value, growable: false),
    );
    _kept[kept] = true;
    if (weight != null) _weights[kept] = weight;
    return kept;
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
    if (_kept[value] == true) return _weights[value] ??= _weigh(value);
    return _weigh(value);
  }

  int _weigh(List<T> value) {
    var n = 16;
    for (final v in value) {
      n += item.weigh(v);
    }
    return n;
  }
}

/// [of], or null.
final class NullableShape<T> extends Shape<T?> {
  const NullableShape(this.of);

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
  T? check(T? value, ITypeContext ctx, {T? was}) =>
      value == null ? null : of.check(value, ctx, was: was);

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

  /// An entry the same as the one kept under its key before, when values
  /// are checked alone, passes unvisited.
  @override
  Map<String, T> check(
    Map<String, T> v,
    ITypeContext ctx, {
    Map<String, T>? was,
  }) {
    if (maxEntries case final m? when v.length > m) {
      throw TypeMismatch('', 'more than $m entries');
    }
    if (_kept[v] == true && value.checkedAlone) return v;
    final before = was != null && _kept[was] == true && value.checkedAlone
        ? was
        : null;
    var same = _kept[v] == true;
    var asBefore = before != null && before.length == v.length;
    final out = <String, T>{};
    for (final MapEntry(:key, value: e) in v.entries) {
      final had = before != null && before.containsKey(key);
      if (had && identical(e, before[key])) {
        out[key] = e;
        continue;
      }
      final T c;
      try {
        c = value.check(e, ctx, was: had ? before[key] : null);
      } on TypeMismatch catch (x) {
        throw _within(key, x);
      }
      if (asBefore && !(had && identical(c, before[key]))) asBefore = false;
      if (same && !identical(c, e)) same = false;
      out[key] = c;
    }
    if (asBefore) return before!;
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
    if (_kept[v] == true) return _weights[v] ??= _weigh(v);
    return _weigh(v);
  }

  int _weigh(Map<String, T> v) {
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
/// written here, beside the fields, and nowhere else. [get], when given
/// (the generator gives it), reads a field by its place in [fields], so a
/// value is checked, compared and weighed with no map made of it.
final class RecordShape<T> extends Shape<T> {
  const RecordShape(
    this.fields, {
    required this.to,
    required this.from,
    this.get,
  });

  final Map<String, Part> fields;
  final Map<String, Object?> Function(T value) to;
  final T Function(Map<String, Object?> fields) from;

  /// The field at [index] of [fields] of [value].
  final Object? Function(T value, int index)? get;

  /// No fields: the params of a command that takes none.
  static const none = RecordShape<()>({}, to: _noFields, from: _unit);

  /// Its fields in order, with their names: read once a shape.
  List<(String, Part)> get _parts =>
      _partsOf[this] ??= [for (final e in fields.entries) (e.key, e.value)];

  /// The map [to] gives of [value], with no field it does not have.
  Map<String, Object?> _fieldsOf(T value) {
    final dart = to(value);
    for (final k in dart.keys) {
      if (!fields.containsKey(k)) throw ArgumentError('no field $k');
    }
    return dart;
  }

  @override
  RecordType get type => RecordType({
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
        if (dart[key] != null || (p.shape is NullableShape && !p.optional))
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
      v != null || (p.shape is NullableShape && !p.optional);

  /// Checks each field as `RecordType` checks it, in the same order, and
  /// gives a left-out one its default; a new record only when a field
  /// changed.
  @override
  T check(T value, ITypeContext ctx, {T? was}) {
    final get = this.get;
    final dart = get == null ? _fieldsOf(value) : null;
    final before = was == null || get != null ? null : to(was);
    final parts = _parts;
    Map<String, Object?>? changed;
    // Whether every field is the one [was] has: then the value is [was].
    var asWas = was != null;
    for (var i = 0; i < parts.length; i++) {
      final (key, p) = parts[i];
      final v = dart == null ? get!(value, i) : dart[key];
      final w = was == null
          ? null
          : (before == null ? get!(was, i) : before[key]);
      final Object? c;
      try {
        if (_said(p, v)) {
          c = v == null ? null : p.shape.check(v, ctx, was: w);
        } else if (p.defaultValue != null) {
          final json = p.shape.type.check(p.defaultValue, ctx);
          c = p.shape.check(p.shape.fromJson(json), ctx);
        } else if (!p.optional) {
          throw const TypeMismatch('', 'missing');
        } else {
          c = null;
        }
      } on TypeMismatch catch (e) {
        throw _within(key, e);
      }
      if (asWas && !identical(c, w)) asWas = false;
      if (!identical(c, v)) {
        (changed ??= dart != null
                ? Map.of(dart)
                : {
                    for (var j = 0; j < parts.length; j++)
                      parts[j].$1: get!(value, j),
                  })[key] =
            c;
      }
    }
    if (asWas) return was as T;
    if (changed == null) return value;
    return from({
      for (final MapEntry(:key, :value) in changed.entries) key: ?value,
    });
  }

  @override
  bool equals(T a, T b) {
    if (identical(a, b)) return true;
    final get = this.get;
    final x = get == null ? to(a) : null;
    final y = get == null ? to(b) : null;
    final parts = _parts;
    for (var i = 0; i < parts.length; i++) {
      final (key, p) = parts[i];
      final u = x == null ? get!(a, i) : x[key];
      final v = y == null ? get!(b, i) : y[key];
      if (identical(u, v)) continue;
      if (u == null || v == null || !p.shape.equals(u, v)) return false;
    }
    return true;
  }

  @override
  int weigh(T value) {
    final get = this.get;
    final dart = get == null ? to(value) : null;
    final parts = _parts;
    var n = 16;
    for (var i = 0; i < parts.length; i++) {
      final (key, p) = parts[i];
      final v = dart == null ? get!(value, i) : dart[key];
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
/// of one subtype, named by its tag. [tagOf] names a value's variant. A
/// variant it does not know reads as [unknown] makes it (SPEC §25.2); with
/// none, it is an [UnknownValue].
final class UnionShape<T> extends Shape<T> {
  const UnionShape(
    this.key,
    this.variants, {
    required this.tagOf,
    this.descriptions = const {},
    this.unknown,
  });

  final String key;
  final Map<String, RecordShape<T>> variants;
  final String Function(T value) tagOf;

  /// What each variant is for, by its tag (a tool's schema says it).
  final Map<String, String> descriptions;

  /// What a variant added after the code was built reads as, from its
  /// JSON, tag and all (a subtype kept for it, holding the JSON).
  final T Function(Map<String, Object?> json)? unknown;

  @override
  UnionType get type => UnionType(
    key,
    {for (final MapEntry(key: tag, value: v) in variants.entries) tag: v.type},
    descriptions: descriptions,
    unknown: unknown != null,
  );

  @override
  Map<String, Object?> toJson(T value) {
    final tag = tagOf(value);
    final v = variants[tag] ?? (throw ArgumentError('no variant $tag'));
    return {key: tag, ...v.toJson(value)};
  }

  @override
  T fromJson(Object? json) {
    final m = json! as Map<Object?, Object?>;
    final v = variants[m[key]];
    if (v == null) {
      if (unknown case final made?) {
        return made({for (final e in m.entries) '${e.key}': e.value});
      }
      throw UnknownValue('${m[key]}', [...variants.keys]);
    }
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
  T check(T value, ITypeContext ctx, {T? was}) => _variant(value).check(
    value,
    ctx,
    was: was != null && tagOf(was) == tagOf(value) ? was : null,
  );

  @override
  bool equals(T a, T b) =>
      identical(a, b) || (tagOf(a) == tagOf(b) && _variant(a).equals(a, b));

  /// Its variant's fields, and the tag beside them.
  @override
  int weigh(T value) =>
      _variant(value).weigh(value) + 32 + key.length + tagOf(value).length;
}

final Expando<(Shape<Object?>, Object?)> _decoded = Expando('decoded');

/// [decodeWith], but none for a value [shape] cannot read, told to
/// [unreadable] (SPEC §25.2): what a typed read gives code built against
/// the word otherwise, rather than throw in it. The value passed the
/// word's type as defined, so [shape] failing on it means the code holds
/// the word otherwise: an enum value or a variant it does not know (an
/// [UnknownValue]), a field it needs left out, a class's own decoder
/// failing.
T? decodeKnown<T>(
  Shape<T> shape,
  Object? json, [
  void Function(Object error)? unreadable,
]) {
  try {
    return decodeWith(shape, json);
  } on Object catch (e) {
    unreadable?.call(e);
    return null;
  }
}

/// The value [shape] makes of [json], null for none. JSON a registry or a
/// mirror tells is frozen, so one decoded value serves every read of the
/// same JSON; a write puts another JSON there.
T? decodeWith<T>(Shape<T> shape, Object? json) {
  if (json == null) return null;
  if (json is! List && json is! Map) return shape.fromJson(json);
  final cached = _decoded[json];
  if (cached != null && identical(cached.$1, shape)) return cached.$2 as T;
  final value = shape.fromJson(json);
  _decoded[json] = (shape, value);
  return value;
}
