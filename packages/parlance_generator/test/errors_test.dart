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
      '@StateWord("total") double get total;',
      'num or int, not double',
    ),
    'positional params of a command': (
      '@CommandWord("cancel") void cancel(String id);',
      'params are named parameters',
    ),
    'an abstract member that says no word': (
      'int get count;',
      'count is abstract but no word',
    ),
    'two members of one name': (
      '@CommandWord("cancel") void a();\n'
          '@CommandWord("cancel") void b();',
      'orders.cancel is said twice',
    ),
    'a query that answers nothing': (
      '@QueryWord("page") void page();',
      'a query answers',
    ),
    'a type a word cannot carry': (
      '@StateWord("any") Set<int> get any;',
      'Set<int> is no type a word can carry',
    ),
    'a bad name': (
      '@StateWord("Big") int get big;',
      'big: "Big" is no name of a word',
    ),
    'a name joined by a space': (
      '@StateWord("muted talk") bool get mutedTalk;',
      'of lower-case letters, digits, _ and -',
    ),
    'a dot in a name': (
      '@CommandWord("order.cancel") void cancel();',
      'no .; a version is version: 2',
    ),
    'a name that reads as a version': (
      '@FactWord("v2") void spoke();',
      '"v2" reads as a version: a version is version: 2',
    ),
    'a first version said': (
      '@CommandWord("cancel", version: 1) void cancel();',
      'a version past the first is 2 or more',
    ),
    'a word named as what every object has': (
      '@StateWord("hash_code") int get hashCode;',
      'hashCode is a name every owner base has',
    ),
    'a bound of a duration on what is no Duration': (
      '@CommandWord("wait") void wait({@Longest(Duration(seconds: 1)) required int ms});',
      '@Longest bounds a Duration',
    ),
    'a fact with a param named by': (
      '@FactWord("spoke") void spoke({required String by});',
      "a fact's param is not named by",
    ),
    'two members of the owner base of one name': (
      '@CommandWord("go", whyNot: true) void go();\n'
          '@CommandWord("why_not_go") void whyNotGo();',
      'whyNotGo is had twice by OrdersOwnerBase',
    ),
    'a word named as what every client has': (
      '@StateWord("status") int get status;',
      'status is had twice by IOrdersClient',
    ),
  };
  for (final MapEntry(key: what, value: (body, says)) in cases.entries) {
    test('it refuses $what', () async {
      final logs = await errorsOf(body);
      expect(logs.join('\n'), contains(says));
    });
  }

  test('it refuses a vocabulary of more than one word', () async {
    final logs = await errorsOf(
      '@StateWord("open") bool get open;',
      '',
      "@Vocabulary('orders.archive')",
    );
    expect(logs.join('\n'), contains('"orders.archive" is no name of a'));
  });

  test('it refuses a kind that is no name', () async {
    final logs = await errorsOf(
      "@CommandWord('go') void go({@ChoiceOf('a.b') required String room});",
    );
    expect(logs.join('\n'), contains('choices "a.b" is no name'));
  });

  test('it refuses an enum with two fallbacks', () async {
    final logs = await errorsOf(
      '@StateWord("mode") Mode get mode;',
      'enum Mode { @Fallback() a, @Fallback() b }',
    );
    expect(logs.join('\n'), contains('one value at most is its @Fallback'));
  });
}
