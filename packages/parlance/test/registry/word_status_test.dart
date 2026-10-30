import 'package:parlance/schema.dart';
import 'package:test/test.dart';

void main() {
  test('a status says why a word cannot be used, as a call result does', () {
    expect(const WordReady().why, isNull);
    expect(const WordMissing().why, 'it is not there');
    expect(const WordNotPermitted().why, 'it is not permitted');
    expect(const WordUnavailable('the door is open').why, 'the door is open');
    expect(
      const WordMismatch([WordBreak('type.max', BreakKind.bound, 10, 5)]).why,
      startsWith('it is not as this code was built against: '),
    );
  });
}
