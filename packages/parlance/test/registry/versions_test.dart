import 'package:parlance/registry.dart';
import 'package:test/test.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const owner = Principal('host');

void main() {
  late Registry r;
  setUp(() => r = Registry());
  tearDown(() => r.dispose());

  StateDescriptor state(String name) =>
      StateDescriptor(name, type: const TextType());

  test('a version is a word of its own, beside the one before it', () {
    final v1 = r.defineState(state('orders.order'), by: owner)..set('a');
    final v2 = r.defineState(state('orders.order.v2'), by: owner)..set('b');
    expect((r.read('orders.order'), r.read('orders.order.v2')), ('a', 'b'));
    v1.dispose();
    expect(r.read('orders.order.v2'), 'b', reason: 'one goes, the other stays');
    v2.dispose();
  });

  test('version 1 is the name alone: one name for a word, never two', () {
    for (final bad in [
      'orders.order.v1',
      'orders.order.v0',
      'orders.v02',
      'v2',
      'orders.v2.cancel',
    ]) {
      expect(() => state(bad), throwsArgumentError, reason: bad);
      expect(() => r.alias(bad, 'x.y'), throwsArgumentError, reason: bad);
    }
    for (final ok in ['orders.v2', 'orders.order.v10', 'orders.vip.cancel']) {
      expect(state(ok).name, ok);
    }
  });

  test('a name tells the word it is a version of', () {
    expect(wordVersion('orders.order'), (word: 'orders.order', version: 1));
    expect(wordVersion('orders.order.v3'), (word: 'orders.order', version: 3));
    expect(wordVersion('orders.vip'), (
      word: 'orders.vip',
      version: 1,
    ), reason: 'a word that only starts with v');
  });
}
