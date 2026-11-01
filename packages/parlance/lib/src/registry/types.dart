import 'json.dart';

/// What a type check needs from the registry: the choices there are.
abstract interface class ITypeContext {
  /// Whether someone gives the choices of [name].
  bool hasChoices(String name);

  /// Whether [id] is one of the choices of [name] right now.
  bool hasChoice(String name, String id);
}

/// A value that does not pass its type.
final class TypeMismatch implements Exception {
  /// Const constructor.
  const TypeMismatch(this.path, this.message);

  /// Where in the value, dot-separated; empty for the value itself.
  final String path;

  /// What was expected there.
  final String message;

  @override
  String toString() => path.isEmpty ? message : '$path: $message';
}

/// The type of a value: checks it and fills defaults (SPEC §2).
///
/// Types are values themselves: [toJson] and [ValueType.fromJson] carry them
/// to clients for `describe`. [T] is the Dart type of the values it passes,
/// for typed words (`PlainShape(BoolType())` is a `Shape<bool>`).
sealed class ValueType<T> {
  const ValueType();

  /// [value] with defaults filled, or a [TypeMismatch].
  Object? check(Object? value, ITypeContext ctx, [String path = '']);

  /// This type as JSON; [ValueType.fromJson] reads it back.
  Map<String, Object?> toJson();

  /// [json] as a type; an object a newer parlance has becomes an
  /// [UnknownType], kept as it came (SPEC §14).
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
      'duration' => DurationType(maxMillis: n('max')?.toInt()),
      'datetime' => const DateTimeType(),
      'ref' => ChoiceType(json['kind'] as String),
      'list' => ListType(
        ValueType.fromJson(json['item']),
        maxItems: n('maxItems')?.toInt(),
      ),
      'object' => RecordType({
        for (final e in (json['fields'] as Map).entries)
          e.key as String: Field.fromJson(e.value),
      }),
      'map' => MapType(
        ValueType.fromJson(json['value']),
        maxEntries: n('maxEntries')?.toInt(),
      ),
      'oneOf' => UnionType(
        json['key'] as String,
        {
          for (final e in (json['variants'] as Map).entries)
            e.key as String: RecordType.fromJson(e.value),
        },
        descriptions: {
          for (final e in (json['descriptions'] as Map? ?? const {}).entries)
            e.key as String: e.value as String,
        },
        unknown: json['unknown'] == true,
      ),
      'nullable' => NullableType(ValueType.fromJson(json['of'])),
      'any' => const AnyType(),
      // A type of a newer parlance (SPEC §14): kept as it came.
      _ => UnknownType(json.cast<String, Object?>()),
    };
  }

  static Never _fail(String path, String message) =>
      throw TypeMismatch(path, message);
}

/// A boolean.
final class BoolType extends ValueType<bool> {
  /// Const constructor.
  const BoolType();

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) =>
      value is bool ? value : ValueType._fail(path, 'expected a bool');

  @override
  Map<String, Object?> toJson() => {'type': 'bool'};
}

/// An integer, [min] to [max].
final class IntType extends ValueType<int> {
  /// Const constructor.
  const IntType({this.min, this.max});

  /// The least it may be.
  final int? min;

  /// The most it may be.
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

/// A number, [min] to [max]; not NaN, not infinite.
final class NumType extends ValueType<num> {
  /// Const constructor.
  const NumType({this.min, this.max});

  /// The least it may be.
  final num? min;

  /// The most it may be.
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

/// A text, at most [maxLength] characters.
final class TextType extends ValueType<String> {
  /// Const constructor.
  const TextType({this.maxLength});

  /// The most characters it may hold.
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

/// One of [values].
final class EnumType extends ValueType<String> {
  /// Const constructor.
  const EnumType(this.values, {this.unknown});

  /// The values it may be.
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
  /// Const constructor.
  const DurationType({this.maxMillis});

  /// The longest, in milliseconds.
  final int? maxMillis;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    final v = const IntType(min: 0).check(value, ctx, path) as int;
    if (maxMillis case final m? when v > m) {
      ValueType._fail(path, 'above $m ms');
    }
    return v;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'duration', 'max': ?maxMillis};
}

/// A moment, as an ISO-8601 text (as json_serializable makes of a
/// DateTime), read back as DateTime.parse has it. The one JSON shape a
/// DateTime has, a word of its own or a field of a JSON class.
final class DateTimeType extends ValueType<String> {
  /// Const constructor.
  const DateTimeType();

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    if (value is! String || DateTime.tryParse(value) == null) {
      ValueType._fail(path, 'expected an ISO-8601 moment');
    }
    return value;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'datetime'};
}

/// One of the choices of [of] (`room`), as its owner gives them: which
/// must be there when checked. Told as `ref` on the wire.
final class ChoiceType extends ValueType<String> {
  /// Const constructor.
  const ChoiceType(this.of);

  /// The choices it is one of: the `name` of the `choices` that gives them.
  final String of;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) {
    if (value is! String || value.isEmpty) {
      ValueType._fail(path, 'expected a $of id');
    }
    if (!ctx.hasChoices(of)) {
      ValueType._fail(
        path,
        'no one gives the choices of $of: its owner says them, '
        "choices(name: '$of', list: ...)",
      );
    }
    if (!ctx.hasChoice(of, value)) ValueType._fail(path, 'no $of $value');
    return value;
  }

  @override
  Map<String, Object?> toJson() => {'type': 'ref', 'kind': of};
}

/// A list of [item], at most [maxItems] long.
final class ListType extends ValueType<List<Object?>> {
  /// Const constructor.
  const ListType(this.item, {this.maxItems});

  /// The type of each item.
  final ValueType<Object?> item;

  /// The most items it may hold.
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

/// A field of a [RecordType].
final class Field {
  /// Const constructor; `optional` becomes true whenever there is a
  /// [defaultValue].
  const Field(
    this.type, {
    bool optional = false,
    this.defaultValue,
    this.description,
  }) : optional = optional || defaultValue != null;

  /// [json] as a field; not an object is a [FormatException], as a type
  /// of its own is.
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

  /// What its values must pass.
  final ValueType<Object?> type;

  /// May be left out; true whenever there is a [defaultValue].
  final bool optional;

  /// What a left-out field becomes.
  final Object? defaultValue;

  /// This field as JSON; [Field.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'type': type.toJson(),
    if (optional) 'optional': true,
    'default': ?defaultValue,
    'description': ?description,
  };
}

/// A map with named fields: unknown ones are refused, left-out optional
/// ones (or null) get their default.
final class RecordType extends ValueType<Map<String, Object?>> {
  /// Const constructor.
  const RecordType(this.fields);

  /// [json] as an object type: params, a variant. Another type (one a
  /// newer parlance has) is a [FormatException], as a word of it is.
  factory RecordType.fromJson(Object? json) =>
      switch (ValueType.fromJson(json)) {
        final RecordType o => o,
        final t => throw FormatException('not an object type: ${t.toJson()}'),
      };

  /// What each named field must pass.
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
  /// Const constructor.
  const MapType(this.value, {this.maxEntries});

  /// The type of each entry's value.
  final ValueType<Object?> value;

  /// The most entries it may hold.
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
final class UnionType extends ValueType<Map<String, Object?>> {
  /// Const constructor.
  const UnionType(
    this.key,
    this.variants, {
    this.descriptions = const {},
    this.unknown = false,
  });

  /// The field that tells the variant apart: its value names one of
  /// [variants].
  final String key;

  /// What each variant's fields must pass, by its tag.
  final Map<String, RecordType> variants;

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
  /// Const constructor.
  const NullableType(this.of);

  /// The type of a value that is not null.
  final ValueType<Object?> of;

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) =>
      value == null ? null : of.check(value, ctx, path);

  @override
  Map<String, Object?> toJson() => {'type': 'nullable', 'of': of.toJson()};
}

/// A type a newer parlance has and this one does not (SPEC §14), read
/// from the wire as its JSON and told on as it came: a participant does
/// not stop at a word of it, and the rule finds it another type than the
/// code holds. A value of it is not checked here, the host that defined
/// the word checks it; and a registry takes no word of it
/// ([unknownTypeIn]), not knowing what its values may be.
final class UnknownType extends ValueType<Object?> {
  /// Const constructor.
  const UnknownType(this.json);

  /// The type as it came from the wire.
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
  RecordType(:final fields) =>
    fields.values.map((f) => unknownTypeIn(f.type)).nonNulls.firstOrNull,
  UnionType(:final variants) =>
    variants.values.map(unknownTypeIn).nonNulls.firstOrNull,
  _ => null,
};

/// Any JSON value: an object, a list, a text, a number, a bool or null.
final class AnyType extends ValueType<Object?> {
  /// Const constructor.
  const AnyType();

  @override
  Object? check(Object? value, ITypeContext ctx, [String path = '']) =>
      isJsonValue(value) ? value : ValueType._fail(path, 'not a JSON value');

  @override
  Map<String, Object?> toJson() => {'type': 'any'};
}
