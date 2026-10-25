import 'package:parlance/links.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

final class MemoryStore implements ILinksStore {
  List<Map<String, Object?>> kept = [];
  int saves = 0;

  @override
  List<Map<String, Object?>> load() => kept;

  @override
  void save(List<Map<String, Object?>> links) {
    kept = links;
    saves++;
  }
}

Map<String, Object?> say(String id, String text, {bool enabled = true}) => {
  'id': id,
  if (!enabled) 'enabled': false,
  'when': [
    {'manual': <String, Object?>{}},
  ],
  'do': [
    {
      'call': 'test.say',
      'params': {'text': text},
    },
  ],
};

void main() {
  late LinksFixture f;
  late MemoryStore store;
  late Links links;

  setUp(() async {
    f = LinksFixture();
    // One engine to a registry: the fixture's goes for this one.
    await f.links.dispose();
    store = MemoryStore()..kept = [say('mine', 'mine')];
    links = Links(f.r, store: store, onError: (e, s) => throw e);
  });
  tearDown(() => links.dispose());

  Future<void> press(String id) =>
      f.r.call('links.press', {'link': id, 'wait': true}, by: user);

  test('own links load from the store and run without a source', () async {
    expect(links.statuses['mine']!.state, LinkState.active);
    await press('mine');
    expect(f.said, ['mine']);
    expect(f.r.read('links.own'), store.kept);
  });

  test(
    "sources come first; an own link of a source's id replaces it",
    () async {
      links.source('host', [say('a', 'host a'), say('b', 'host b')]);
      expect(links.links.keys, ['a', 'b', 'mine']);
      await f.r.call('links.upsert', {'link': say('a', 'own a')}, by: user);
      expect(links.links.keys, ['a', 'b', 'mine'], reason: 'in its place');
      await press('a');
      expect(f.said, ['own a']);
      await f.r.call('links.upsert', {
        'link': say('b', 'x', enabled: false),
      }, by: user);
      expect(links.statuses['b']!.state, LinkState.off);
    },
  );

  test("a source turned off takes its links with it, the user's own that "
      'replace them too; dropped, those stay the user\'s', () async {
    links.source('plugin:kittens', [say('k.a', 'a'), say('k.b', 'b')]);
    await f.r.call('links.upsert', {'link': say('k.a', 'own a')}, by: user);
    expect(
      links.originOf('k.a'),
      const LinkOrigin('plugin:kittens', edited: true),
    );
    expect(links.originOf('k.b'), const LinkOrigin('plugin:kittens'));
    expect(links.originOf('mine'), const LinkOrigin(null));
    links.source('plugin:kittens', [
      say('k.a', 'a'),
      say('k.b', 'b'),
    ], on: false);
    expect(links.statuses['k.a']!.state, LinkState.off);
    expect(links.statuses['k.b']!.state, LinkState.off);
    links.source('plugin:kittens', [say('k.a', 'a'), say('k.b', 'b')]);
    await press('k.a');
    expect(f.said, ['own a']);
    links.dropSource('plugin:kittens');
    expect(links.links.keys, ['mine', 'k.a']);
    expect(links.originOf('k.a'), const LinkOrigin(null));
    expect(links.originOf('k.b'), isNull);
  });

  test('set, upsert and remove go through the store', () async {
    expect(
      (await f.r.call('links.set', {
        'links': [say('one', '1'), say('two', '2')],
      }, by: user)).ok,
      isTrue,
    );
    expect([for (final l in store.kept) l['id']], ['one', 'two']);
    await f.r.call('links.upsert', {'link': say('three', '3')}, by: user);
    await f.r.call('links.remove', {'id': 'one'}, by: user);
    expect([for (final l in store.kept) l['id']], ['two', 'three']);
    expect(links.links.keys, ['two', 'three']);
    expect(store.saves, 3);
  });

  test(
    'a bad set is refused whole; a link of a source cannot be removed',
    () async {
      final bad = await f.r.call('links.set', {
        'links': [
          say('ok', 'x'),
          {
            'id': 'bad',
            'when': [
              {'fact': 'Not A Name'},
            ],
            'do': <Object?>[],
          },
          say('ok', 'twice'),
        ],
      }, by: user);
      expect(bad, isA<CallFailed>());
      expect(
        '${(bad as CallFailed).error}',
        allOf(contains('bad'), contains('ok: id twice')),
      );
      expect(store.kept.single['id'], 'mine', reason: 'unchanged');
      links.source('host', [say('a', 'a')]);
      expect(
        await f.r.call('links.remove', {'id': 'a'}, by: user),
        isA<CallFailed>(),
      );
    },
  );

  test('check tells what a link lacks without applying it', () async {
    final ok = await f.r.call('links.check', {'link': say('x', 'x')}, by: user);
    expect((ok as CallDone).value, {
      'ok': true,
      'problems': <String>[],
      'missing': <String>[],
    });
    final lacks = await f.r.call('links.check', {
      'link': {
        'id': 'y',
        'when': [
          {'fact': 'plugin.thing'},
        ],
        'do': <Object?>[],
      },
    }, by: user);
    expect(((lacks as CallDone).value as Map)['missing'], ['plugin.thing']);
    expect(links.links.containsKey('y'), isFalse);
  });

  test('reloadOwn takes what the host changed in the store', () async {
    store.kept = [say('other', 'o')];
    links.reloadOwn();
    expect(links.links.keys, ['other']);
    await press('other');
    expect(f.said, ['o']);
  });
}
