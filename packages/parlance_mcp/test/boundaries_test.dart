import 'dart:io';

import 'package:test/test.dart';

/// The tools work on a participant, here or across a connection, so they
/// know no transport; only the binary does.
void main() {
  test('the library does not import rpc_dart', () {
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final imports = RegExp(
        r'''^import '([^']+)';''',
        multiLine: true,
      ).allMatches(e.readAsStringSync()).map((m) => m[1]!);
      for (final i in imports) {
        expect(i, isNot(startsWith('package:rpc_dart')), reason: e.path);
      }
    }
  });
}
