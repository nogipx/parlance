import 'package:parlance/tools.dart';

/// [t] as JSON Schema, for an agent's tool (SPEC §16). [kinds] are the
/// entities by kind, as `describe` lists them: a ref to a kind with any
/// becomes a choice of their ids.
Map<String, Object?> jsonSchema(
  ValueType<Object?> t, {
  Map<String, List<Map<String, Object?>>> kinds = const {},
}) => switch (t) {
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
  DurationType(:final max) => {
    'type': 'integer',
    'minimum': 0,
    'maximum': ?max,
    'description': 'milliseconds',
  },
  ChoiceType(:final of) => {
    'type': 'string',
    'description': 'a $of',
    if (kinds[of] case final e? when e.isNotEmpty)
      'enum': [for (final x in e) x['id']],
  },
  ListType(:final item, :final maxItems) => {
    'type': 'array',
    'items': jsonSchema(item, kinds: kinds),
    'maxItems': ?maxItems,
  },
  ObjectType() => _object(t, kinds),
  MapType(:final value, :final maxEntries) => {
    'type': 'object',
    'additionalProperties': jsonSchema(value, kinds: kinds),
    'maxProperties': ?maxEntries,
  },
  OneOfType(:final key, :final variants, :final descriptions) => {
    'oneOf': [
      for (final MapEntry(key: tag, value: o) in variants.entries)
        {
          ..._object(o, kinds, tag: (key, tag)),
          'description': ?descriptions[tag],
        },
    ],
  },
  NullableType(:final of) => {
    'anyOf': [
      jsonSchema(of, kinds: kinds),
      {'type': 'null'},
    ],
  },
  // A type of a newer parlance is any value, as far as an agent is told.
  CustomType() || AnyType() || UnknownType() => const {},
};

Map<String, Object?> _object(
  ObjectType o,
  Map<String, List<Map<String, Object?>>> kinds, {
  (String, String)? tag,
}) => {
  'type': 'object',
  'properties': {
    if (tag case (final key, final value)) key: {'const': value},
    for (final MapEntry(:key, value: f) in o.fields.entries)
      key: {
        ...jsonSchema(f.type, kinds: kinds),
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
