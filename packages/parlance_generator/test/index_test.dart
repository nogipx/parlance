import 'package:test/test.dart';

import 'fixtures/index/_index.dart';

/// Vocabularies of one library, said as its parts.
void main() {
  test('vocabularies in parts of one library share what they carry', () {
    expect(doorsWords.name, 'door');
    expect(lightsWords.name, 'light');
    expect(
      DoorsState.room.shape,
      same(LightsCommand.on.params.fields['room']!.shape),
    );
  });
}
