import 'package:parlance/tools.dart';

/// [t] as JSON Schema, for an agent's tool (SPEC §16).
Map<String, Object?> jsonSchema(ValueType<Object?> t) => switch (t) {
  BoolType() => {'type': 'boolean'},
  IntType(:final min, :final max) => {
    'type': 'integer',
    'minimum': ?min,
    'maximum': ?max,
  },
  NumType(:final min, :final max) => {
    'type': 'number',
    'minimum': ?min,
    'maximum': ?max,
  },
  TextType(:final maxLength) => {'type': 'string', 'maxLength': ?maxLength},
  EnumType(:final values) => {'type': 'string', 'enum': values},
  DurationType(maxMillis: final max) => {
    'type': 'integer',
    'minimum': 0,
    'maximum': ?max,
    'description': 'milliseconds',
  },
  DateTimeType() => {
    'type': 'integer',
    'description': 'milliseconds since the epoch, UTC',
  },
  ListType(:final item, :final maxItems) => {
    'type': 'array',
    'items': jsonSchema(item),
    'maxItems': ?maxItems,
  },
  RecordType() => _object(t),
  MapType(:final value, :final maxEntries) => {
    'type': 'object',
    'additionalProperties': jsonSchema(value),
    'maxProperties': ?maxEntries,
  },
  UnionType(:final key, :final variants, :final descriptions) => {
    'oneOf': [
      for (final MapEntry(key: tag, value: o) in variants.entries)
        {..._object(o, tag: (key, tag)), 'description': ?descriptions[tag]},
    ],
  },
  NullableType(:final of) => {
    'anyOf': [
      jsonSchema(of),
      {'type': 'null'},
    ],
  },
  // A type of a newer parlance is any value, as far as an agent is told.
  AnyType() || UnknownType() => const {},
};

Map<String, Object?> _object(RecordType o, {(String, String)? tag}) => {
  'type': 'object',
  'properties': {
    if (tag case (final key, final value)) key: {'const': value},
    for (final MapEntry(:key, value: f) in o.fields.entries)
      key: {
        ...jsonSchema(f.type),
        'description': ?f.description,
        'default': ?f.defaultValue,
      },
  },
  'required': [
    if (tag case (final key, _)) key,
    for (final e in o.fields.entries)
      if (!e.value.optional) e.key,
  ],
  'additionalProperties': false,
};
