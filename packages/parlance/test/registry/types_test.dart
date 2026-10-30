import 'package:parlance/tools.dart';
import 'package:test/test.dart';

final class _Ctx implements ITypeContext {
  @override
  bool hasChoices(String kind) => kind == 'room';

  @override
  bool hasChoice(String kind, String id) => kind == 'room' && id == 'main';
}

void main() {
  final ctx = _Ctx();
  Object? ok(ValueType<Object?> t, Object? v) => t.check(v, ctx);
  Matcher fails(String text) =>
      throwsA(isA<TypeMismatch>().having((e) => '$e', 'text', contains(text)));

  test('primitives', () {
    expect(ok(const BoolType(), true), true);
    expect(() => ok(const BoolType(), 1), fails('bool'));
    expect(ok(const IntType(min: 0, max: 3), 2.0), 2);
    expect(() => ok(const IntType(max: 3), 4), fails('above 3'));
    expect(() => ok(const IntType(), 1.5), fails('integer'));
    expect(ok(const NumType(min: -1), 0.5), 0.5);
    expect(() => ok(const NumType(), double.nan), fails('number'));
    expect(() => ok(const TextType(maxLength: 2), 'abc'), fails('longer'));
    expect(ok(const EnumType(['a', 'b']), 'b'), 'b');
    expect(() => ok(const EnumType(['a']), 'c'), fails('one of'));
    expect(ok(const DurationType(), 1500), 1500);
    expect(() => ok(const DurationType(), -1), fails('below 0'));
  });

  test('refs need a registered kind and an entity in it', () {
    expect(ok(const ChoiceType('room'), 'main'), 'main');
    expect(() => ok(const ChoiceType('room'), 'gone'), fails('no room gone'));
    expect(
      () => ok(const ChoiceType('lamp'), 'x'),
      fails('no one gives the choices of lamp'),
    );
  });

  test('objects fill defaults and refuse unknown and missing fields', () {
    const t = RecordType({
      'a': Field(IntType()),
      'b': Field(TextType(), defaultValue: 'x'),
      'c': Field(BoolType(), optional: true),
    });
    expect(ok(t, {'a': 1}), {'a': 1, 'b': 'x'});
    expect(() => ok(t, {'a': 1, 'z': 2}), fails('z: unknown field'));
    expect(() => ok(t, {'b': 'y'}), fails('a: missing'));
    expect(
      () => ok(const ListType(t), [
        {'a': 'no'},
      ]),
      fails('0.a: expected an integer'),
    );
  });

  test('a nullable type takes none, or what its type takes', () {
    const t = NullableType(ListType(TextType()));
    expect(ok(t, null), isNull);
    expect(ok(t, ['a']), ['a']);
    expect(() => ok(t, 'a'), fails('expected a list'));
  });

  test('types round-trip through JSON', () {
    const t = RecordType({
      'room': Field(ChoiceType('room')),
      'n': Field(IntType(min: 1, max: 5), defaultValue: 2),
      'tags': Field(ListType(EnumType(['x', 'y']), maxItems: 3)),
      'd': Field(DurationType(maxMillis: 1000), optional: true),
      'any': Field(AnyType()),
      'maybe': Field(NullableType(ListType(TextType()))),
    });
    final back = ValueType.fromJson(t.toJson());
    expect(back.toJson(), t.toJson());
  });

  test('values freeze and compare deeply', () {
    final v = freezeJson({
      'a': [1, 2],
      'b': {'c': true},
    });
    expect(() => (v as Map)['a'] = 1, throwsUnsupportedError);
    expect(
      jsonEquals(v, {
        'a': [1.0, 2],
        'b': {'c': true},
      }),
      isTrue,
    );
    expect(jsonEquals([1], [1, 2]), isFalse);
    expect(() => freezeJson(Object()), throwsArgumentError);
    expect(
      jsonAt({
        'a': [
          {'b': 3},
        ],
      }, 'a.0.b'),
      3,
    );
  });

  test('an optional field given as null is left out', () {
    const t = RecordType({
      'a': Field(TextType(), optional: true),
      'b': Field(IntType(), defaultValue: 3),
      'c': Field(TextType()),
    });
    expect(t.check({'a': null, 'b': null, 'c': 'x'}, ctx), {'b': 3, 'c': 'x'});
    expect(() => t.check({'c': null}, ctx), throwsA(isA<TypeMismatch>()));
  });
}
