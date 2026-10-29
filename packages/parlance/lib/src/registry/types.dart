import 'json.dart';

/// What a type check needs from the registry: entity kinds and the host's
/// own types.
abstract interface class ITypeContext {
  /// Whether an entity kind named [kind] is registered.
  bool hasKind(String kind);

  /// Whether the kind [kind] holds an entity [id] right now.
  bool hasEntity(String kind, String id);

  /// Null when the host's type [name] accepts [value], else why not.
  String? checkCustom(String name, Object? value);
}

/// A value that does not pass its type.
final class TypeMismatch implements Exception {
  const TypeMismatch(this.path, this.message);

  /// Where in the value, dot-separated; empty for the value itself.
  final String path;
  final String message;

  @override
  String toString() => path.isEmpty ? message : '$path: $message';
}

/// The type of a value: checks it and fills defaults (SPEC §2).
///
/// Types are values themselves: [toJson] and [ValueType.fromJson] carry them
/// to clients for `describe`. [T] is the Dart type of the values it passes,
/// for typed words (`Plain(BoolType())` is a `Shape<bool>`).
sealed class ValueType<T> {
  const ValueType();

  /// [value] with defaults filled, or a [TypeMismatch].
  Object? check(Object? value, ITypeContext ctx, [String path = '']);

  Map<String, Object?> toJson();

  static ValueType<Object?> fromJson(Object? json) {
    if (json is! Map) throw FormatException('a type is an object: $json');
    num? n(String k) => json[k] as num?;
    return switch (json['type']) {
      'bool' => const BoolType(),
      'int' => IntType(min: n('min')?.toInt(), max: n('max')?.toInt()),
      'num' => NumType(min: n('min'), max: n('max')),
      'text' => TextType(maxLength: n('maxLength')?.toInt()),
      'enum' => EnumType([
        for (final v in json['values'] as List) v as String,
      ], unknown: json['unknown'] as String?),
      'duration' => DurationType(max: n('max')?.toInt()),
      'ref' => RefType(json['kind'] as String),
      'list' => ListType(
        ValueType.fromJson(json['item']),
        maxItems: n('maxItems')?.toInt(),
      ),
      'object' => ObjectType({
        for (final e in (json['fields'] as Map).entries)
          e.key as String: Field.fromJson(e.value),
      }),
      'map' => MapType(
        ValueType.fromJson(json['value']),
        maxEntries: n('maxEntries')?.toInt(),
      ),
      'oneOf' => OneOfType(
        json['key'] as String,
        {
          for (final e in (json['variants'] as Map).entries)
            e.key as String: ObjectType.fromJson(e.value),
        },
        descriptions: {
          for (final e in (json['descriptions'] as Map? ?? const {}).entries)
            e.key as String: e.value as String,
        },
        unknown: json['unknown'] == true,
      ),
      'nullable' => NullableType(ValueType.fromJson(json['of'])),
      'custom' => CustomType(json['name'] as String),
      'any' => const AnyType(),
      // A type of a newer parlance (SPEC §14): kept as it came.
      _ => UnknownType(json.cast<String, Object?>()),
    };
  }

  static Never _fail(String path, String message) =>
      throw TypeMismatch(path, message);
}

final class BoolType extends ValueType<bool> {
  const BoolType();

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) =>
      value is bool ? value : ValueType._fail(path, 'expected a bool');

  @override
  Map<String, Object?> toJson() => {'type': 'bool'};
}

final class IntType extends ValueType<int> {
  const IntType({this.min, this.max});

  final int? min;
  final int? max;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    final v = switch (value) {
      int() => value,
      double() when value == value.roundToDouble() && value.isFinite =>
        value.toInt(),
      _ => ValueType._fail(path, 'expected an integer'),
    };
    if (min case final m? when v < m) ValueType._fail(path, 'below $m');
    if (max case final m? when v > m) ValueType._fail(path, 'above $m');
    return v;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'int', 'min': ?min, 'max': ?max};
}

final class NumType extends ValueType<num> {
  const NumType({this.min, this.max});

  final num? min;
  final num? max;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    if (value is! num || !value.isFinite) {
      ValueType._fail(path, 'expected a number');
    }
    if (min case final m? when value < m) ValueType._fail(path, 'below $m');
    if (max case final m? when value > m) ValueType._fail(path, 'above $m');
    return value;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'num', 'min': ?min, 'max': ?max};
}

final class TextType extends ValueType<String> {
  const TextType({this.maxLength});

  final int? maxLength;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    if (value is! String) ValueType._fail(path, 'expected text');
    if (maxLength case final m? when value.length > m) {
      ValueType._fail(path, 'longer than $m');
    }
    return value;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'text', 'maxLength': ?maxLength};
}

final class EnumType extends ValueType<String> {
  const EnumType(this.values, {this.unknown});

  final List<String> values;

  /// What code reading it takes a value it does not know for, one of
  /// [values] (SPEC §25.2), as Avro's reader takes its enum's default:
  /// code built before a value was added goes on reading. Null when it
  /// has none. Writes are checked against [values] all the same.
  final String? unknown;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) =>
      value is String && values.contains(value)
      ? value
      : ValueType._fail(path, 'expected one of ${values.join(', ')}');

  @override
  Map<String, Object?> toJson() => {
    'type': 'enum',
    'values': values,
    'unknown': ?unknown,
  };
}

/// A duration as whole milliseconds.
final class DurationType extends ValueType<int> {
  const DurationType({this.max});

  /// The longest, in milliseconds.
  final int? max;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    final v = const IntType(min: 0).check(value, ctx, path) as int;
    if (max case final m? when v > m) ValueType._fail(path, 'above $m ms');
    return v;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'duration', 'max': ?max};
}

/// The id of an entity of [kind], which must exist when checked.
final class RefType extends ValueType<String> {
  const RefType(this.kind);

  final String kind;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    if (value is! String || value.isEmpty) {
      ValueType._fail(path, 'expected a $kind id');
    }
    if (!ctx.hasKind(kind)) ValueType._fail(path, 'no entity kind $kind');
    if (!ctx.hasEntity(kind, value)) ValueType._fail(path, 'no $kind $value');
    return value;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'ref', 'kind': kind};
}

final class ListType extends ValueType<List<Object?>> {
  const ListType(this.item, {this.maxItems});

  final ValueType<Object?> item;
  final int? maxItems;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    if (value is! List) ValueType._fail(path, 'expected a list');
    if (maxItems case final m? when value.length > m) {
      ValueType._fail(path, 'more than $m items');
    }
    return [
      for (var i = 0; i < value.length; i++)
        item.check(value[i], ctx, path.isEmpty ? '$i' : '$path.$i'),
    ];
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'list',
    'item': item.toJson(),
    'maxItems': ?maxItems,
  };
}

/// A field of an [ObjectType].
final class Field {
  const Field(
    this.type, {
    bool optional = false,
    this.defaultValue,
    this.description,
  }) : optional = optional || defaultValue != null;

  factory Field.fromJson(Object? json) {
    final m = json as Map;
    return Field(
      ValueType.fromJson(m['type']),
      optional: m['optional'] == true,
      defaultValue: m['default'],
      description: m['description'] as String?,
    );
  }

  /// What it is, for people and agents.
  final String? description;

  final ValueType<Object?> type;

  /// May be left out; true whenever there is a [defaultValue].
  final bool optional;

  /// What a left-out field becomes.
  final Object? defaultValue;

  Map<String, Object?> toJson() => {
    'type': type.toJson(),
    if (optional) 'optional': true,
    'default': ?defaultValue,
    'description': ?description,
  };
}

/// A map with named fields: unknown ones are refused, left-out optional
/// ones (or null) get their default.
final class ObjectType extends ValueType<Map<String, Object?>> {
  const ObjectType(this.fields);

  /// [json] as an object type: params, a variant. Another type (one a
  /// newer parlance has) is a [FormatException], as a word of it is.
  factory ObjectType.fromJson(Object? json) =>
      switch (ValueType.fromJson(json)) {
        final ObjectType o => o,
        final t => throw FormatException('not an object type: ${t.toJson()}'),
      };

  final Map<String, Field> fields;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    if (value is! Map) ValueType._fail(path, 'expected an object');
    String at(String k) => path.isEmpty ? k : '$path.$k';
    for (final k in value.keys) {
      if (k is! String || !fields.containsKey(k)) {
        ValueType._fail(at('$k'), 'unknown field');
      }
    }
    final out = <String, Object?>{};
    for (final MapEntry(key: k, value: f) in fields.entries) {
      // An optional field given as null is left out, as JSON writers often
      // say it; but where null is a value of its own (a nullable field), it
      // is that value, not its default.
      if (value.containsKey(k) &&
          !(value[k] == null && f.optional && f.type is! NullableType)) {
        out[k] = f.type.check(value[k], ctx, at(k));
      } else if (f.defaultValue != null) {
        out[k] = f.type.check(f.defaultValue, ctx, at(k));
      } else if (!f.optional) {
        ValueType._fail(at(k), 'missing');
      }
    }
    return out;
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'object',
    'fields': {for (final e in fields.entries) e.key: e.value.toJson()},
  };
}

/// A map from any text to values of [value]: files by path, refs by name.
final class MapType extends ValueType<Map<String, Object?>> {
  const MapType(this.value, {this.maxEntries});

  final ValueType<Object?> value;
  final int? maxEntries;

  @override
  Object? check(Object? v, ITypeContext ctx, [String path = '']) {
    if (v is! Map) ValueType._fail(path, 'expected an object');
    if (maxEntries case final m? when v.length > m) {
      ValueType._fail(path, 'more than $m entries');
    }
    return {
      for (final e in v.entries)
        if (e.key is! String)
          '${e.key}': ValueType._fail(path, 'keys are text')
        else
          e.key as String: value.check(
            e.value,
            ctx,
            path.isEmpty ? '${e.key}' : '$path.${e.key}',
          ),
    };
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'map',
    'value': value.toJson(),
    'maxEntries': ?maxEntries,
  };
}

/// One of several objects, told apart by the text in field [key]: its value
/// names the variant, whose fields the rest must pass.
final class OneOfType extends ValueType<Map<String, Object?>> {
  const OneOfType(
    this.key,
    this.variants, {
    this.descriptions = const {},
    this.unknown = false,
  });

  final String key;
  final Map<String, ObjectType> variants;

  /// What each variant is for, by its tag, for people and agents.
  final Map<String, String> descriptions;

  /// Whether code reading it takes a variant it does not know for one of
  /// its own (SPEC §25.2), so a variant added breaks none of it. Writes
  /// are checked against [variants] all the same.
  final bool unknown;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    if (value is! Map) ValueType._fail(path, 'expected an object');
    final tag = value[key];
    final at = path.isEmpty ? key : '$path.$key';
    final variant = variants[tag];
    if (variant == null) {
      ValueType._fail(at, 'one of ${variants.keys.join(', ')}');
    }
    final rest = {
      for (final e in value.entries)
        if (e.key != key) e.key: e.value,
    };
    return {key: tag, ...variant.check(rest, ctx, path) as Map};
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'oneOf',
    'key': key,
    'variants': {for (final e in variants.entries) e.key: e.value.toJson()},
    if (descriptions.isNotEmpty) 'descriptions': descriptions,
    if (unknown) 'unknown': true,
  };
}

/// [of], or null: "none" as a value of its own, apart from an empty list
/// or a zero.
final class NullableType extends ValueType<Object?> {
  const NullableType(this.of);

  final ValueType<Object?> of;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) =>
      value == null ? null : of.check(value, ctx, path);

  @override
  Map<String, Object?> toJson() => {'type': 'nullable', 'of': of.toJson()};
}

/// A type of the host's: the registry asks the host's checker.
final class CustomType extends ValueType<Object?> {
  const CustomType(this.name);

  final String name;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    if (!isJsonValue(value)) ValueType._fail(path, 'not a JSON value');
    if (ctx.checkCustom(name, value) case final why?) {
      ValueType._fail(path, why);
    }
    return value;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'custom', 'name': name};
}

/// A type a newer parlance has and this one does not (SPEC §14), read
/// from the wire as its JSON and told on as it came: a participant does
/// not stop at a word of it, and the rule finds it another type than the
/// code holds. A value of it is not checked here, the host that defined
/// the word checks it; and a registry takes no word of it
/// ([unknownTypeIn]), not knowing what its values may be.
final class UnknownType extends ValueType<Object?> {
  const UnknownType(this.json);

  final Map<String, Object?> json;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) => value;

  @override
  Map<String, Object?> toJson() => json;
}

/// The first [UnknownType] in [type], however deep; null when there is
/// none.
UnknownType? unknownTypeIn(ValueType<Object?>? type) => switch (type) {
  null => null,
  final UnknownType u => u,
  ListType(:final item) => unknownTypeIn(item),
  MapType(:final value) => unknownTypeIn(value),
  NullableType(:final of) => unknownTypeIn(of),
  ObjectType(:final fields) =>
    fields.values.map((f) => unknownTypeIn(f.type)).nonNulls.firstOrNull,
  OneOfType(:final variants) =>
    variants.values.map(unknownTypeIn).nonNulls.firstOrNull,
  _ => null,
};

final class AnyType extends ValueType<Object?> {
  const AnyType();

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) =>
      isJsonValue(value) ? value : ValueType._fail(path, 'not a JSON value');

  @override
  Map<String, Object?> toJson() => {'type': 'any'};
}
