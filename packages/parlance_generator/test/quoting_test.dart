import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:parlance_generator/builder.dart';
import 'package:test/test.dart';

/// A text the generator puts in code is code of the same text, whatever
/// it holds: quotes, a dollar, a backslash, lines.
void main() {
  final parlance = {
    for (final f in Directory('../parlance/lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        'parlance|lib/${f.path.substring('../parlance/lib/'.length)}': f
            .readAsStringSync(),
  };

  test('a description of lines is code that parses', () async {
    String? made;
    await testBuilder(
      parlanceBuilder(BuilderOptions.empty),
      {
        ...parlance,
        'a|lib/words.dart': r"""
import 'package:parlance/registry.dart';
import 'package:parlance/schema.dart';
part 'words.g.dart';

@Vocabulary('orders')
abstract class Orders {
  @CommandWord()
  void say({
    @Describe('''one 'line'
two \$lines, \\ and\r\nthree''')
    required String text,
  });
}
""",
      },
      rootPackage: 'a',
      generateFor: {'a|lib/words.dart'},
      outputs: {
        'a|lib/words.parlance.g.part': decodedMatches(
          predicate<String>((s) {
            made = s;
            return true;
          }),
        ),
      },
    );
    expect(made, isNotNull);
    expect(() => parseString(content: made!), returnsNormally);
    expect(made, contains(r"'one \'line\'\ntwo \$lines, \\ and\r\nthree'"));
  });
}
