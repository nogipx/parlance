import 'package:parlance/registry.dart';
import 'package:parlance/testing.dart';
import 'package:rpc_dart/logger.dart';
import 'package:test/test.dart';

import 'fixture.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

void main() {
  test('what follows from a message is in its conversation, however far, '
      'and a cause made by hand naming only its parent too', () async {
    final r = Registry();
    final said = r.defineFact(
      FactDescriptor('chat.line', type: const TextType()),
      by: owner,
    );
    final clipped = r.defineState(
      StateDescriptor('clip.last', type: const TextType()),
      by: owner,
    );
    r.defineCommand(
      CommandDescriptor('chat.say', callers: Callers.only(['user'])),
      (c) => said.emit('!clip', cause: c.causeFor(owner)),
    );
    r.defineCommand(
      CommandDescriptor('clip.save', callers: Callers.only(['user'])),
      (c) => clipped.set('clip-1', cause: c.causeFor(owner)),
    );
    // A listener answers the fact with a cause it makes itself.
    r
        .facts(fact: 'chat.line')
        .listen(
          (f) => r.call(
            'clip.save',
            {},
            by: user,
            cause: Cause(user, parent: f.id),
          ),
        );
    await r.call('chat.say', {}, by: user, id: 'start');
    await pumpEventQueue();

    final talk = r.conversation('start');
    expect([for (final c in talk.calls) c.command], ['chat.say', 'clip.save']);
    expect([for (final f in talk.facts) f.fact], ['chat.line']);
    expect([for (final c in talk.changes) c.state], ['clip.last']);
    expect(r.lastChange('clip.last')!.cause.conversation, 'start');
    expect(r.conversation('another').isEmpty, isTrue);
    await r.dispose();
  });

  test('the message a conversation started with stays with all that '
      'follows, whoever acts on the way; a message that follows from '
      'nothing is its own origin, whatever it claims', () async {
    final r = Registry();
    const viewer = Principal('viewer', 'twitch.7');
    const plugin = Principal('plugin', 'basics');
    final said = r.defineFact(
      FactDescriptor('chat.line', type: const TextType()),
      by: owner,
    );
    final clipped = r.defineState(
      StateDescriptor('clip.last', type: const TextType()),
      by: owner,
    );
    r.defineCommand(
      CommandDescriptor('chat.say', callers: Callers.only(['viewer'])),
      (c) => said.emit('!clip', cause: c.causeFor(owner)),
    );
    r.defineCommand(
      CommandDescriptor('clip.save', callers: Callers.only(['plugin'])),
      (c) => clipped.set('clip-1', cause: c.causeFor(owner)),
    );
    // The plugin names the fact it answers, and claims another origin.
    r
        .facts(fact: 'chat.line')
        .listen(
          (f) => r.call(
            'clip.save',
            {},
            by: plugin,
            id: 'save',
            cause: Cause(
              plugin,
              parent: f.id,
              origin: const Origin('audio.mute', user),
            ),
          ),
        );
    await r.call('chat.say', {}, by: viewer, id: 'irc:1');
    await pumpEventQueue();
    const started = Origin('chat.say', viewer);
    final talk = r.conversation('irc:1');
    expect(
      [for (final c in talk.calls) (c.command, c.cause.originOf(c.command))],
      [('chat.say', started), ('clip.save', started)],
    );
    expect(talk.calls.first.cause.origin, isNull, reason: 'it started it');
    expect(talk.facts.single.cause.origin, started);
    expect(r.lastChange('clip.last')!.cause.origin, started);
    expect(r.lastChange('clip.last')!.cause.by, owner);
    expect(Origin.fromJson(started.toJson()), started);

    await r.call(
      'clip.save',
      {},
      by: plugin,
      id: 'claims',
      cause: const Cause(plugin, origin: started),
    );
    expect(r.callRecord('claims')!.cause.origin, isNull);
    await r.dispose();
  });

  test('calls a handler makes, and the calls theirs make, have the origin '
      'of the first, with nothing passed but the call\'s cause', () async {
    final r = Registry();
    const viewer = Principal('viewer', 'twitch.7');
    for (final (name, next) in [
      ('a.go', ['b.go']),
      ('b.go', ['c.go', 'd.go']),
      ('c.go', <String>[]),
      ('d.go', <String>[]),
    ]) {
      r.defineCommand(
        CommandDescriptor(name, callers: Callers.only(['viewer', 'host'])),
        (c) async {
          for (final n in next) {
            await r.call(n, {}, by: owner, cause: c.causeFor(owner));
          }
        },
      );
    }
    await r.call('a.go', {}, by: viewer, id: 'start');
    final calls = r.conversation('start').calls;
    const started = Origin('a.go', viewer);
    expect(
      [
        for (final c in calls)
          (c.command, c.cause.by, c.cause.originOf(c.command)),
      ],
      [
        ('c.go', owner, started),
        ('d.go', owner, started),
        ('b.go', owner, started),
        ('a.go', viewer, started),
      ],
    );
    expect(calls.last.cause.origin, isNull, reason: 'the first is its own');
    await r.dispose();
  });

  test('across a connection, what an owner does in answer stays in the '
      'conversation', () async {
    final host = TestHost();
    final p = await host.join(
      const Principal('plugin', 'clips'),
      vocabularies: [WordSet.open('clips')],
    );
    final last = p.defineState(
      StateDescriptor('clips.last', type: const TextType()),
    );
    p.defineCommand(
      CommandDescriptor('clips.save', callers: Callers.only(['user'])),
      (c) => last.set('clip-1', cause: c.causeFor(p.who)),
    );
    await p.flush();
    await host.registry.call('clips.save', {}, by: user, id: 'press');
    await host.settle();
    expect(host.registry.lastChange('clips.last')!.cause.conversation, 'press');
    expect(
      host.registry.lastChange('clips.last')!.cause.origin,
      const Origin('clips.save', user),
    );
    await host.dispose();
  });

  test('a span tells its conversation', () async {
    final logs = LogController();
    final spans = <LogSpan>[];
    logs.stream.listen((r) {
      if (r is LogSpan) spans.add(r);
    });
    final f = Fixture(
      registry: Registry(log: logs.scope('p'), onError: (e, _) {}),
    );
    await f.r.call('audio.mute', {'on': true}, by: user, id: 'm');
    await pumpEventQueue();
    expect(spans.single.data, containsPair('conversation', 'm'));
    expect(spans.single.data, containsPair('origin', 'audio.mute'));
    expect(spans.single.data, containsPair('originBy', 'user/local'));
    await f.r.dispose();
    logs.dispose();
  });
}
