import 'package:parlance/registry.dart';
import 'package:test/test.dart';

/// The rule a word is held to (SPEC §25.1), as the data goes: what code
/// built against a word reads, it must read as the word gives it now;
/// what it gives, the word must take now.
Map<String, Object?> _state(ValueType<Object?> t) => {
  'is': 'state',
  'type': t.toJson(),
};

Map<String, Object?> _command(
  Map<String, Field> params, [
  ValueType<Object?>? returns,
]) => {
  'is': 'command',
  'params': ObjectType(params).toJson(),
  if (returns != null) 'returns': returns.toJson(),
};

List<String> _said(Object? built, Object? live) => [
  for (final b in entryBreaks(built, live)) '$b',
];

const _point = ObjectType({
  'x': Field(IntType()),
  'y': Field(IntType(), optional: true),
});

void main() {
  group('fingerprints', fingerprints);

  group('what code reads', () {
    test('a field added is skipped', () {
      expect(
        _said(
          _state(_point),
          _state(
            const ObjectType({
              'x': Field(IntType()),
              'y': Field(IntType(), optional: true),
              'z': Field(TextType()),
            }),
          ),
        ),
        isEmpty,
      );
    });

    test('a field gone breaks it where it needs it, not where it may do '
        'without', () {
      expect(
        _said(
          _state(_point),
          _state(const ObjectType({'y': Field(IntType())})),
        ),
        ['type.fields.x: was required, is nothing'],
      );
      expect(
        _said(
          _state(_point),
          _state(const ObjectType({'x': Field(IntType())})),
        ),
        isEmpty,
      );
    });

    test('a bound narrowed is read; one widened may not be', () {
      expect(
        _said(_state(const IntType(max: 100)), _state(const IntType(max: 50))),
        isEmpty,
      );
      final wider = entryBreaks(
        _state(const IntType(max: 100)),
        _state(const IntType()),
      );
      expect(wider, [
        const WordBreak('type.max', BreakKind.bound, 100, null, certain: false),
      ], reason: 'only a value past 100 breaks it');
    });

    test('an integer reads where a number is read, not the other way', () {
      expect(_said(_state(const NumType()), _state(const IntType())), isEmpty);
      expect(_said(_state(const IntType()), _state(const NumType())), [
        'type.type: was int, is num',
      ]);
    });

    test('a value made nullable breaks it; one made sure does not', () {
      expect(
        _said(_state(const IntType()), _state(const NullableType(IntType()))),
        ['type.type: was int, is nullable'],
      );
      expect(
        _said(_state(const NullableType(IntType())), _state(const IntType())),
        isEmpty,
      );
    });

    test('an enum value added may break it; one gone does not', () {
      expect(
        entryBreaks(
          _state(const EnumType(['a', 'b'])),
          _state(const EnumType(['a', 'b', 'c'])),
        ),
        [
          const WordBreak(
            'type.values',
            BreakKind.value,
            ['a', 'b'],
            ['a', 'b', 'c'],
            certain: false,
          ),
        ],
      );
      expect(
        _said(
          _state(const EnumType(['a', 'b'])),
          _state(const EnumType(['a'])),
        ),
        isEmpty,
      );
    });

    test('an answer gone breaks what reads it, unless it may be none', () {
      expect(_said(_command(const {}, const IntType()), _command(const {})), [
        'returns: was int, is nothing',
      ]);
      expect(
        _said(
          _command(const {}, const NullableType(IntType())),
          _command(const {}),
        ),
        isEmpty,
      );
    });
  });

  group('what code gives', () {
    test('a param added it may leave out is no break; one it must give is', () {
      final before = _command({'x': const Field(IntType())});
      expect(
        _said(
          before,
          _command({
            'x': const Field(IntType()),
            'y': const Field(IntType(), optional: true),
          }),
        ),
        isEmpty,
      );
      expect(
        _said(
          before,
          _command({'x': const Field(IntType()), 'y': const Field(IntType())}),
        ),
        ['params.fields.y: was nothing, is required'],
      );
    });

    test('a param gone is refused when it is given', () {
      final gone = entryBreaks(
        _command({
          'x': const Field(IntType()),
          'y': const Field(IntType(), optional: true),
        }),
        _command({}),
      );
      expect(gone, [
        const WordBreak('params.fields.x', BreakKind.field, 'required', null),
        const WordBreak(
          'params.fields.y',
          BreakKind.field,
          'optional',
          null,
          certain: false,
        ),
      ]);
    });

    test('a bound widened takes it; one narrowed may not', () {
      expect(
        _said(
          _command({'x': const Field(IntType(max: 5))}),
          _command({'x': const Field(IntType(max: 10))}),
        ),
        isEmpty,
      );
      expect(
        _said(
          _command({'x': const Field(TextType(maxLength: 200))}),
          _command({'x': const Field(TextType(maxLength: 100))}),
        ),
        ['params.fields.x.type.maxLength: was 200, is 100'],
      );
    });

    test('an enum value added takes it; one gone may not', () {
      expect(
        _said(
          _command({
            'm': const Field(EnumType(['a'])),
          }),
          _command({
            'm': const Field(EnumType(['a', 'b'])),
          }),
        ),
        isEmpty,
      );
      expect(
        _said(
          _command({
            'm': const Field(EnumType(['a', 'b'])),
          }),
          _command({
            'm': const Field(EnumType(['a'])),
          }),
        ),
        ['params.fields.m.type.values: was [a, b], is [a]'],
      );
    });
  });

  test('another kind of word is one break, and nothing under it', () {
    expect(_said(_state(const IntType()), _command(const {})), [
      'is: was state, is command',
    ]);
  });

  test('every break is said at once, as JSON too', () {
    final breaks = entryBreaks(
      _command({
        'a': const Field(IntType()),
        'b': const Field(TextType(maxLength: 9)),
      }),
      _command({
        'a': const Field(TextType()),
        'b': const Field(TextType(maxLength: 3)),
      }),
    );
    expect(
      [for (final b in breaks) '$b'],
      [
        'params.fields.a.type.type: was int, is text',
        'params.fields.b.type.maxLength: was 9, is 3',
      ],
    );
    expect(breaks.last.toJson(), {
      'path': 'params.fields.b.type.maxLength',
      'kind': 'bound',
      'was': 9,
      'is': 3,
      'certain': false,
    });
  });
}

void fingerprints() {
  test('a schema in another order of keys, or described otherwise, is one '
      'fingerprint; another type is another', () {
    final a = _command({
      'x': const Field(IntType(max: 3), description: 'how many'),
      'description': const Field(TextType()),
    });
    final reordered = {
      'params': {
        'fields': {
          'description': {
            'type': {'type': 'text'},
          },
          'x': {
            'type': {'max': 3, 'type': 'int'},
          },
        },
        'type': 'object',
      },
      'is': 'command',
    };
    expect(fingerprintOf(reordered), fingerprintOf(a));
    expect(
      fingerprintOf(_command({'x': const Field(IntType(max: 4))})),
      isNot(fingerprintOf(a)),
    );
    expect(
      canonicalSchema(a),
      contains('"description":{"type":{"type":"text"}}'),
      reason: 'a field named description is a field',
    );
    expect(
      fingerprintOf({'a.go': a}),
      fingerprintOf({'a.go': reordered}),
      reason: 'a schema of words too',
    );
  });
}
