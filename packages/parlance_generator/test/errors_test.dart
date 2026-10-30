import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:parlance_generator/builder.dart';
import 'package:test/test.dart';

/// What the generator refuses, and that it says why.
void main() {
  // The annotations and the registry, as the module's code imports them.
  final parlance = {
    for (final f in Directory('../parlance/lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        'parlance|lib/${f.path.substring('../parlance/lib/'.length)}': f
            .readAsStringSync(),
  };

  Future<List<String>> errorsOf(
    String body, [
    String top = '',
    String vocabulary = "@Vocabulary('orders')",
  ]) async {
    final logs = <String>[];
    await testBuilder(
      parlanceBuilder(BuilderOptions.empty),
      {
        ...parlance,
        'a|lib/words.dart':
            '''
import 'package:parlance/tools.dart';
import 'package:parlance/schema.dart';
part 'words.g.dart';

$top

$vocabulary
abstract class Orders {
$body
}
''',
      },
      rootPackage: 'a',
      generateFor: {'a|lib/words.dart'},
      onLog: (r) => logs.add(r.message),
    );
    return logs;
  }

  final cases = {
    'a number as double': (
      '@StateWord() double get total;',
      'num or int, not double',
    ),
    'positional params of a command': (
      '@CommandWord() void cancel(String id);',
      'params are named parameters',
    ),
    'an abstract member that says no word': (
      'int get count;',
      'count is abstract but no word',
    ),
    'two members of one name': (
      '@CommandWord(name: "cancel") void a();\n'
          '@CommandWord(name: "cancel") void b();',
      'orders.cancel is said twice',
    ),
    'a query that answers nothing': (
      '@QueryWord() void page();',
      'a query answers',
    ),
    'a type a word cannot carry': (
      '@StateWord() Set<int> get any;',
      'Set<int> is no type a word can carry',
    ),
    'a bad name': (
      '@StateWord(name: "Big") int get big;',
      'big: "orders.Big" is no word name',
    ),
    'a name joined by a space': (
      '@StateWord(name: "muted talk") bool get mutedTalk;',
      'joined by _ or -',
    ),
    'a version not last': (
      '@CommandWord(name: "v2.cancel") void cancel();',
      'a version is the last word only',
    ),
    'a word named as what every object has': (
      '@StateWord() int get hashCode;',
      'hashCode is a name every owner base has',
    ),
    'a fact with a param named by': (
      '@FactWord() void spoke({required String by});',
      "a fact's param is not named by",
    ),
    'two members of the owner base of one name': (
      '@CommandWord(whyNot: true) void go();\n'
          '@CommandWord() void whyNotGo();',
      'whyNotGo is had twice by OrdersOwnerBase',
    ),
    'a word named as what the owner base keeps it said': (
      '@StateWord() int get said;',
      'said is a name every owner base has',
    ),
    'two members of the client of one name': (
      '@StateWord() int get total;\n@CommandWord() void totalChanges();',
      'totalChanges is had twice by OrdersClient',
    ),
  };
  for (final MapEntry(key: what, value: (body, says)) in cases.entries) {
    test('it refuses $what', () async {
      final logs = await errorsOf(body);
      expect(logs.join('\n'), contains(says));
    });
  }

  test('it refuses a kind that is no name', () async {
    final logs = await errorsOf(
      "@CommandWord() void go({@ChoiceOf('a.b') required String room});",
    );
    expect(logs.join('\n'), contains('choices "a.b" is no name'));
  });

  test('it refuses an enum with two fallbacks', () async {
    final logs = await errorsOf(
      '@StateWord() Mode get mode;',
      'enum Mode { @Fallback() a, @Fallback() b }',
    );
    expect(logs.join('\n'), contains('one value at most is its @Fallback'));
  });
}
