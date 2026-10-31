import 'package:clock/clock.dart';
import 'package:parlance/testing.dart';
import 'package:parlance/tools.dart';
import 'package:test/test.dart';

/// A keyed state's whole map reads each value as one key's read does
/// (`IKeyedOf.all` as `of`): wherever the participant is, a value that
/// cannot be read is left out, not thrown; in the host's process the
/// owner's own values come as they are.
final class Stock {
  Stock(this.n);
  final int n;
}

final stock = JsonShape<Stock>(
  from: (m) => Stock(m['n']! as int),
  to: (s) => {'n': s.n},
);

const shop = Principal('shop');
const reader = Principal('reader');

void main() {
  late TestHost host;
  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  for (final across in [false, true]) {
    test('${across ? 'across a connection' : 'in this process'}: a value '
        'that cannot be read is left out of all, keys and changes, as of '
        'answers null for it', () async {
      final own = host.participant(shop, vocabularies: [WordSet.open('shop')]);
      final stockOf = own.raw.defineState(
        StateDescriptor('shop.stock', type: const AnyType(), key: 'item'),
      );
      stockOf.set({'n': 1}, key: 'a');
      stockOf.set('oops', key: 'b');
      final IParticipant p = across
          ? await host.join(reader)
          : host.participant(reader);
      final keyed = GeneratedWords(
        p,
      ).keyedOf(StateWordOf<Stock>('shop.stock', stock, key: 'item'));
      final seen = <Map<String, Stock>>[];
      final sub = keyed.changes.listen(seen.add);
      await p.settle();
      await host.settle();

      expect(keyed.of('b'), isNull);
      expect(keyed.all.keys, ['a']);
      expect(keyed.all['a']!.n, 1);
      expect(keyed.keys, ['a']);
      expect(seen.last.keys, ['a']);
      await sub.cancel();
    });
  }

  for (final across in [false, true]) {
    test('${across ? 'across a connection' : 'in this process'}: a stored '
        'null is a key there is: has tells it from a missing one, as of '
        'answers null for both', () async {
      final own = host.participant(shop, vocabularies: [WordSet.open('shop')]);
      final stockOf = own.raw.defineState(
        StateDescriptor('shop.stock', type: const AnyType(), key: 'item'),
      );
      stockOf.set(null, key: 'a');
      final IParticipant p = across
          ? await host.join(reader)
          : host.participant(reader);
      final keyed = GeneratedWords(
        p,
      ).keyedOf(StateWordOf<Stock>('shop.stock', stock, key: 'item'));
      final sub = keyed.changes.listen((_) {});
      await p.settle();
      await host.settle();

      expect(keyed.has('a'), isTrue);
      expect(keyed.of('a'), isNull);
      expect(keyed.has('b'), isFalse);
      await sub.cancel();
    });
  }

  test('in this process, all gives the values the owner keeps, as of '
      'does', () async {
    const at = DateTimeShape();
    final own = host.participant(shop, vocabularies: [WordSet.open('shop')]);
    // Kept as it is, the handle takes the value itself.
    final when = own.raw.defineState(
      StateDescriptor('shop.when', type: at.type, key: 'item'),
      shape: at,
    );
    final kept = DateTime.utc(2020);
    when.set(kept, key: 'a');
    final keyed = GeneratedWords(
      host.participant(reader),
    ).keyedOf(const StateWordOf<DateTime>('shop.when', at, key: 'item'));
    expect(keyed.of('a'), same(kept));
    expect(keyed.all['a'], same(kept));
  });

  test('changesOf tells one key alone', () async {
    final own = host.participant(shop, vocabularies: [WordSet.open('shop')]);
    final stockOf = own.raw.defineState(
      StateDescriptor('shop.stock', type: const AnyType(), key: 'item'),
    );
    stockOf.set({'n': 1}, key: 'a');
    stockOf.set({'n': 1}, key: 'b');
    final keyed = GeneratedWords(
      host.participant(reader),
    ).keyedOf(StateWordOf<Stock>('shop.stock', stock, key: 'item'));
    final seen = <int>[];
    final sub = keyed.changesOf('a').listen((s) => seen.add(s!.n));
    await host.settle();

    stockOf.set({'n': 2}, key: 'a');
    await host.settle();
    stockOf.set({'n': 3}, key: 'b');
    await host.settle();
    expect(seen, [1, 2], reason: 'the other key does not tell it');
    await sub.cancel();
  });

  test('a participant joined to a test host reads the time by its '
      'clock', () async {
    final at = DateTime.utc(2020);
    final timed = TestHost(clock: Clock.fixed(at));
    addTearDown(timed.dispose);
    final p = await timed.join(reader);
    expect(p.raw.clock.now(), at);
  });
}
