import 'package:parlance/registry.dart';
import 'package:parlance/testing.dart';
import 'package:parlance/view.dart';
import 'package:test/test.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const owner = Principal('host', 'studio');

void main() {
  test('a view told the changes of an old name hears the word', () async {
    final r = Registry();
    final w = r.defineState(
      StateDescriptor('a.now', type: const IntType()),
      by: owner,
    );
    r.alias('a.old', 'a.now');
    var told = 0;
    LocalView(r, by: owner).changes({'a.old'}).listen((_) => told++);
    w.set(1);
    await Future<void>.delayed(Duration.zero);
    expect(told, 1);
  });

  test(
    'across a connection, the facts of an old name are the word\'s',
    () async {
      final host = TestHost();
      addTearDown(host.dispose);
      final said = host.registry.defineFact(
        FactDescriptor('a.said', type: const IntType()),
        by: owner,
      );
      host.registry.alias('a.told', 'a.said');
      final p = await host.join(const Principal('viewer', 'v'));
      final heard = <Object?>[];
      p.facts('a.told').listen((f) => heard.add(f.payload));
      await host.settle();
      said.emit(7);
      await host.settle();
      expect(heard, [7]);
    },
  );
}
