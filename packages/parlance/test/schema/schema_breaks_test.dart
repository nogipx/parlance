import 'package:parlance/schema.dart';
import 'package:test/test.dart';

Map<String, Object?> _command(Map<String, Field> params) => {
  'a.go': {'is': 'command', 'params': RecordType(params).toJson()},
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
      ['a.go: params.fields.y: was nothing, is required'],
    );
    expect(schemaBreaks(before, _command({'x': const Field(TextType())})), [
      'a.go: params.fields.x.type.type: was int, is text',
    ]);
    expect(schemaBreaks(before, const {}), ['a.go is gone']);
  });

  test('held to every release still in use, or to the latest', () {
    final v1 = _command({'x': const Field(IntType(max: 10))});
    final v2 = _command({'x': const Field(IntType(max: 5))});
    final now = _command({'x': const Field(IntType(max: 5))});
    final releases = {'1.0.0': v1, '2.0.0': v2};
    expect(breaksSince(releases, now), {
      '1.0.0': ['a.go: params.fields.x.type.max: was 10, is 5'],
    }, reason: 'what 2.0.0 accepted on purpose still breaks 1.0.0');
    expect(breaksSince(releases, now, latest: true), isEmpty);
  });
}
