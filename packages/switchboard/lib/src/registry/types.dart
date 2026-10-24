import 'json.dart';

/// What a type check needs from the registry: entity kinds and the host's
/// own types.
abstract interface class TypeContext {
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
/// to clients for `describe`.
sealed class ValueType {
  const ValueType();

  /// [value] with defaults filled, or a [TypeMismatch].
  Object? check(Object? value, TypeContext ctx, [String path = '']);

  Map<String, Object?> toJson();

  static ValueType fromJson(Object? json) {
    if (json is! Map) throw FormatException('a type is an object: $json');
    num? n(String k) => json[k] as num?;
    return switch (json['type']) {
      'bool' => const BoolType(),
      'int' => IntType(min: n('min')?.toInt(), max: n('max')?.toInt()),
      'num' => NumType(min: n('min'), max: n('max')),
      'text' => TextType(maxLength: n('maxLength')?.toInt()),
      'enum' => EnumType([for (final v in json['values'] as List) v as String]),
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
      'custom' => CustomType(json['name'] as String),
      'any' => const AnyType(),
      final t => throw FormatException('unknown type $t'),
    };
  }

  static Never _fail(String path, String message) =>
      throw TypeMismatch(path, message);
}

final class BoolType extends ValueType {
  const BoolType();

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) =>
      value is bool ? value : ValueType._fail(path, 'expected a bool');

  @override
  Map<String, Object?> toJson() => {'type': 'bool'};
}

final class IntType extends ValueType {
  const IntType({this.min, this.max});

  final int? min;
  final int? max;

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) {
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

final class NumType extends ValueType {
  const NumType({this.min, this.max});

  final num? min;
  final num? max;

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) {
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

final class TextType extends ValueType {
  const TextType({this.maxLength});

  final int? maxLength;

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) {
    if (value is! String) ValueType._fail(path, 'expected text');
    if (maxLength case final m? when value.length > m) {
      ValueType._fail(path, 'longer than $m');
    }
    return value;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'text', 'maxLength': ?maxLength};
}

final class EnumType extends ValueType {
  const EnumType(this.values);

  final List<String> values;

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) =>
      value is String && values.contains(value)
      ? value
      : ValueType._fail(path, 'expected one of ${values.join(', ')}');

  @override
  Map<String, Object?> toJson() => {'type': 'enum', 'values': values};
}

/// A duration as whole milliseconds.
final class DurationType extends ValueType {
  const DurationType({this.max});

  /// The longest, in milliseconds.
  final int? max;

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) {
    final v = const IntType(min: 0).check(value, ctx, path) as int;
    if (max case final m? when v > m) ValueType._fail(path, 'above $m ms');
    return v;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'duration', 'max': ?max};
}

/// The id of an entity of [kind], which must exist when checked.
final class RefType extends ValueType {
  const RefType(this.kind);

  final String kind;

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) {
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

final class ListType extends ValueType {
  const ListType(this.item, {this.maxItems});

  final ValueType item;
  final int? maxItems;

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) {
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
  const Field(this.type, {bool optional = false, this.defaultValue})
    : optional = optional || defaultValue != null;

  factory Field.fromJson(Object? json) {
    final m = json as Map;
    return Field(
      ValueType.fromJson(m['type']),
      optional: m['optional'] == true,
      defaultValue: m['default'],
    );
  }

  final ValueType type;

  /// May be left out; true whenever there is a [defaultValue].
  final bool optional;

  /// What a left-out field becomes.
  final Object? defaultValue;

  Map<String, Object?> toJson() => {
    'type': type.toJson(),
    if (optional) 'optional': true,
    'default': ?defaultValue,
  };
}

/// A map with named fields: unknown ones are refused, left-out optional
/// ones get their default.
final class ObjectType extends ValueType {
  const ObjectType(this.fields);

  final Map<String, Field> fields;

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) {
    if (value is! Map) ValueType._fail(path, 'expected an object');
    String at(String k) => path.isEmpty ? k : '$path.$k';
    for (final k in value.keys) {
      if (k is! String || !fields.containsKey(k)) {
        ValueType._fail(at('$k'), 'unknown field');
      }
    }
    final out = <String, Object?>{};
    for (final MapEntry(key: k, value: f) in fields.entries) {
      if (value.containsKey(k)) {
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

/// A type of the host's: the registry asks the host's checker.
final class CustomType extends ValueType {
  const CustomType(this.name);

  final String name;

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) {
    if (!isJsonValue(value)) ValueType._fail(path, 'not a JSON value');
    if (ctx.checkCustom(name, value) case final why?) {
      ValueType._fail(path, why);
    }
    return value;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'custom', 'name': name};
}

final class AnyType extends ValueType {
  const AnyType();

  @override
  Object? check(Object? value, TypeContext ctx, [String path = '']) =>
      isJsonValue(value) ? value : ValueType._fail(path, 'not a JSON value');

  @override
  Map<String, Object?> toJson() => {'type': 'any'};
}
