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

  Future<List<String>> errorsOf(String body) async {
    final logs = <String>[];
    await testBuilder(
      parlanceBuilder(BuilderOptions.empty),
      {
        ...parlance,
        'a|lib/words.dart':
            '''
import 'package:parlance/registry.dart';
import 'package:parlance/schema.dart';
part 'words.g.dart';

@Vocabulary('orders')
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
      '@StateWord() Object get any;',
      'Object is no type a word can carry',
    ),
    'a bad name': ('@StateWord(name: "Big") int get big;', '"orders.Big"'),
    'a word named as a member of Owner': (
      '@StateWord() int get words;',
      'words is a member of Owner',
    ),
    'setting a state the class has not': (
      '@CommandWord(sets: "total") void put({required int to});',
      'put sets total, which is no state of Orders',
    ),
    'setting a state from one of several params, unsaid': (
      '@StateWord() int get total;\n'
          '@CommandWord(sets: "total") void put({required int to, int? by});',
      'say which param is the value',
    ),
    'setting a keyed state without its key': (
      '@StateWord(key: "order") int get total;\n'
          '@CommandWord(sets: "total") void put({required int to});',
      'total is keyed by order, give setsKey',
    ),
  };
  for (final MapEntry(key: what, value: (body, says)) in cases.entries) {
    test('it refuses $what', () async {
      final logs = await errorsOf(body);
      expect(logs.join('\n'), contains(says));
    });
  }
}
