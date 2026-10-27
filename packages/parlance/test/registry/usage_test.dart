import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  late Fixture f;
  setUp(() => f = Fixture());
  tearDown(() => f.r.dispose());

  test(
    'a call counts as its caller\'s use of the word, refused or not',
    () async {
      await f.r.call('audio.mute', {'on': true}, by: user);
      await f.r.call('audio.mute', {'on': false}, by: user);
      await f.r.call('audio.mute', {'on': true}, by: viewer);
      final uses = {for (final u in f.r.usesOf('audio.mute')) u.by: u};
      expect(uses[user]!.calls, 2);
      expect(uses[viewer]!.calls, 1, reason: 'notPermitted, still a use');
      expect(f.r.usesOf('studio.show'), isEmpty);
    },
  );

  test('an old name is counted as it was named, apart from the word', () async {
    f.r.alias('audio.silence', 'audio.mute');
    await f.r.call('audio.silence', {'on': true}, by: agent);
    expect(f.r.usesOf('audio.silence').single.by, agent);
    expect(f.r.usesOf('audio.mute'), isEmpty);
    expect(f.r.usage.keys, ['audio.silence']);
  });

  test('a name there is no word of keeps nothing', () async {
    await f.r.call('no.such', {}, by: user);
    f.r.usedBy('nor.this', user);
    f.r.listenedBy('nor.that', user).dispose();
    expect(f.r.usage, isEmpty);
  });

  test('past usersPerWord, uses are counted under the kind alone', () async {
    final r = Registry(usersPerWord: 2);
    r.defineCommand(
      CommandDescriptor('chat.clip', callers: Callers.only(['viewer'])),
      (_) {},
    );
    for (final id in ['a', 'b', 'c', 'd']) {
      await r.call('chat.clip', {}, by: Principal('viewer', id));
    }
    final by = {for (final u in r.usesOf('chat.clip')) u.by.selector: u.calls};
    expect(by, {'viewer/a': 1, 'viewer/b': 1, 'viewer': 2});
    await r.dispose();
  });

  test('a listener counts while it listens; a read once', () {
    final h = f.r.listenedBy('audio.muted', viewer);
    expect(f.r.usesOf('audio.muted').single.listening, 1);
    h.dispose();
    f.r.usedBy('audio.muted', viewer);
    final use = f.r.usesOf('audio.muted').single;
    expect((use.listening, use.reads), (0, 1));
    expect(use.toJson()['by'], viewer.selector);
  });

  test('a read by name, as an agent makes it, is its use', () async {
    final p = f.r.participant(agent);
    await p.fetch('audio.muted');
    await p.explain('studio.program');
    expect(f.r.usesOf('audio.muted').single.reads, 1);
    expect(f.r.usesOf('studio.program').single.by, agent);
  });
}
