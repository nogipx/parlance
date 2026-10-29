import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:parlance_generator/builder.dart';
import 'package:test/test.dart';

/// What the generator puts in code is code of the same: a text whatever
/// it holds (quotes, a dollar, a backslash, lines), a constant as the
/// generated part can name it.
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
import 'package:parlance/tools.dart';
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
  test('what is imported with a prefix is named with it', () async {
    String? made;
    await testBuilder(
      parlanceBuilder(BuilderOptions.empty),
      {
        ...parlance,
        'a|lib/who.dart': '''
import 'package:parlance/schema.dart';
const crew = Callers({'crew': Access.allow});
abstract final class Who {
  static const staff = Callers({'staff': Access.allow});
}
enum Mode { open, @Fallback() other }
''',
        'a|lib/words.dart': '''
import 'package:parlance/schema.dart';
import 'who.dart' as who;
part 'words.g.dart';

@Vocabulary('orders')
abstract class Orders {
  @CommandWord(callers: who.crew)
  void cancel();
  @CommandWord(callers: who.Who.staff)
  void close();
  @StateWord()
  who.Mode get mode;
}
''',
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
    expect(made, contains('callers: who.crew'));
    expect(made, contains('callers: who.Who.staff'));
    expect(
      made,
      contains('EnumShape(who.Mode.values, unknown: who.Mode.other)'),
    );
    expect(made, contains('who.Mode? get mode'));
  });
  group('source that is odd', () {
    /// What the builder logged of [words], the library's source.
    Future<String> logsOf(String words) async {
      final logs = <String>[];
      await testBuilder(
        parlanceBuilder(BuilderOptions.empty),
        {...parlance, 'a|lib/words.dart': words},
        rootPackage: 'a',
        generateFor: {'a|lib/words.dart'},
        onLog: (r) => logs.add(r.message),
      );
      return logs.join('\n');
    }

    test('a default that is no JSON number is refused, saying so', () async {
      final logs = await logsOf('''
import 'package:parlance/schema.dart';
part 'words.g.dart';

@Vocabulary('orders')
abstract class Orders {
  @CommandWord()
  void zoom({num ratio = double.infinity});
}
''');
      expect(logs, contains('ratio: a default is a finite number'));
    });

    test(
      'two JSON classes of one name, by two prefixes, are each its own',
      () async {
        String? made;
        const json = '''
class Point {
  Point(this.x);
  factory Point.fromJson(Map<String, Object?> m) => Point(m['x'] as int);
  final int x;
  Map<String, Object?> toJson() => {'x': x};
}
''';
        await testBuilder(
          parlanceBuilder(BuilderOptions.empty),
          {
            ...parlance,
            'a|lib/a.dart': json,
            'a|lib/b.dart': json,
            'a|lib/words.dart': '''
import 'package:parlance/schema.dart';
import 'a.dart' as a;
import 'b.dart' as b;
part 'words.g.dart';

@Vocabulary('orders')
abstract class Orders {
  @StateWord()
  a.Point get from;
  @StateWord()
  b.Point get to;
}
''',
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
        expect(() => parseString(content: made!), returnsNormally);
        final helpers = {
          for (final m in RegExp(
            r'Map<String, Object\?> (\S+)\((\S+) v\)',
          ).allMatches(made!))
            m[1]: m[2],
        };
        expect(helpers.values, unorderedEquals(['a.Point', 'b.Point']));
        final flat = made!.replaceAll(RegExp(r'\s+'), ' ');
        for (final MapEntry(key: helper, value: type) in helpers.entries) {
          expect(flat, contains('$type.fromJson, $helper,'));
        }
      },
    );

    test('a type that does not resolve is refused, saying where', () async {
      final logs = await logsOf('''
import 'package:parlance/schema.dart';
part 'words.g.dart';

@Vocabulary('orders')
abstract class Orders {
  @StateWord()
  Nowhere get place;
}
''');
      expect(logs, contains('place: its type does not resolve here'));
    });
  });
}
