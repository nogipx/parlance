import 'package:parlance/registry.dart';
import 'package:parlance/testing.dart';
import 'package:rpc_dart/logger.dart';
import 'package:test/test.dart';

import 'fixture.dart';

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
    expect(r.lastChange('clip.last')!.cause.correlation, 'start');
    expect(r.conversation('another').isEmpty, isTrue);
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
    expect(host.registry.lastChange('clips.last')!.cause.correlation, 'press');
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
    await f.r.dispose();
    logs.dispose();
  });
}
