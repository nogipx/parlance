import 'package:parlance/schema.dart';
import 'package:test/test.dart';

Map<String, Object?> _command(Map<String, Field> params) => {
  'a.go': {'is': 'command', 'params': ObjectType(params).toJson()},
};

void main() {
  test('a param a caller may leave out is no break; one it must give is', () {
    final before = _command({'x': const Field(IntType())});
    expect(
      schemaBreaks(
        before,
        _command({
          'x': const Field(IntType()),
          'y': const Field(IntType(), optional: true),
          'z': const Field(IntType(), defaultValue: 1),
        }),
      ),
      isEmpty,
    );
    expect(
      schemaBreaks(
        before,
        _command({'x': const Field(IntType()), 'y': const Field(IntType())}),
      ),
      ['a.go changed'],
    );
    expect(schemaBreaks(before, _command({'x': const Field(TextType())})), [
      'a.go changed',
    ]);
  });
}
