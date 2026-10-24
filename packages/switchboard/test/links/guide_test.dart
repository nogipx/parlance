import 'dart:io';

import 'package:switchboard/links.dart';
import 'package:test/test.dart';

/// The guide agents write links by (linkGuide) and the parser read the
/// same keys: a key the parser learns and the guide does not tell fails
/// here.
void main() {
  test('the guide tells every key the parser reads', () {
    final source = File('lib/src/links/model.dart').readAsStringSync();
    final keys = {
      for (final m in RegExp(
        r"\b\w\['(\w+)'\]|containsKey\('(\w+)'\)",
      ).allMatches(source))
        m[1] ?? m[2]!,
    };
    expect(keys, contains('when'));
    final told = RegExp(r'\w+').allMatches(linkGuide).map((m) => m[0]).toSet();
    expect(keys.difference(told), isEmpty);
  });

  test('the guide names the engine by its words', () {
    expect(linkGuide, contains(LinkWords.press));
    expect(linkGuide, contains('${LinkWords.ownPrefix}name'));
  });
}
