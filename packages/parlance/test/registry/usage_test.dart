import 'package:parlance/tools.dart';
import 'package:test/test.dart';

import 'fixture.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

void main() {
  late Fixture f;
  setUp(() => f = Fixture());
  tearDown(() => f.r.dispose());

  test(
    'a call counts as its caller\'s use of the word, refused or not',
    () async {
      await f.r.call('door.lock', {'on': true}, by: user);
      await f.r.call('door.lock', {'on': false}, by: user);
      await f.r.call('door.lock', {'on': true}, by: visitor);
      final uses = {for (final u in f.r.usesOf('door.lock')) u.by: u};
      expect(uses[user]!.calls, 2);
      expect(uses[visitor]!.calls, 1, reason: 'notPermitted, still a use');
      expect(f.r.usesOf('house.show'), isEmpty);
    },
  );

  test('an old name is counted as it was named, apart from the word', () async {
    f.r.alias('door.silence', 'door.lock');
    await f.r.call('door.silence', {'on': true}, by: agent);
    expect(f.r.usesOf('door.silence').single.by, agent);
    expect(f.r.usesOf('door.lock'), isEmpty);
    expect(f.r.usage.keys, ['door.silence']);
  });

  test('a name there is no word of keeps nothing', () async {
    await f.r.call('no.such', {}, by: user);
    f.r.usedBy('nor.this', user);
    expect(f.r.listenedBy('nor.that', user), isNull);
    expect(f.r.usage, isEmpty);
  });

  test('past usersPerWord, uses are counted under the kind alone', () async {
    final r = Registry(limits: HostLimits(usersPerWord: 2));
    r.defineCommand(
      CommandDescriptor('intercom.clip', callers: Callers.only(['visitor'])),
      (_) {},
    );
    for (final id in ['a', 'b', 'c', 'd']) {
      await r.call('intercom.clip', {}, by: Principal('visitor', id));
    }
    final by = {
      for (final u in r.usesOf('intercom.clip')) u.by.selector: u.calls,
    };
    expect(by, {'visitor/a': 1, 'visitor/b': 1, 'visitor': 2});
    await r.dispose();
  });

  test('a listener counts while it listens; a read once', () {
    final h = f.r.listenedBy('door.locked', visitor)!;
    expect(f.r.usesOf('door.locked').single.listening, 1);
    h.dispose();
    f.r.usedBy('door.locked', visitor);
    final use = f.r.usesOf('door.locked').single;
    expect((use.listening, use.reads), (0, 1));
    expect(use.toJson()['by'], visitor.selector);
  });

  test('a read by name, as an agent makes it, is its use', () async {
    final p = f.r.participant(agent);
    await p.fetch('door.locked');
    await p.explain('house.focus');
    expect(f.r.usesOf('door.locked').single.reads, 1);
    expect(f.r.usesOf('house.focus').single.by, agent);
  });

  test(
    'what was counted of a word goes with it, but who listens now',
    () async {
      final r = Registry();
      addTearDown(r.dispose);
      StateDescriptor word() => StateDescriptor('a.x', type: const IntType());
      final first = r.defineState(word(), by: owner);
      r.usedBy('a.x', user);
      final listening = r.listenedBy('a.x', agent)!;
      first.dispose();
      expect(r.usesOf('a.x').map((u) => (u.by, u.listening)), [(agent, 1)]);

      // The word comes again (a plugin reloaded): who listens goes on.
      r.defineState(word(), by: owner);
      r.usedBy('a.x', agent);
      expect(r.usesOf('a.x').map((u) => (u.by, u.reads, u.listening)), [
        (agent, 1, 1),
      ]);
      listening.dispose();
    },
  );

  test('what was counted of an old name goes when the old name does', () async {
    final silence = f.r.alias('door.silence', 'door.lock');
    await f.r.call('door.silence', {'on': true}, by: agent);
    silence.dispose();
    expect(f.r.usesOf('door.silence'), isEmpty);
    expect(f.r.usage, isEmpty);
  });
}
