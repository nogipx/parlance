import 'package:parlance/registry.dart';
import 'package:rpc_dart/logger.dart';
import 'package:test/test.dart';

import 'fixture.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

/// The journal (SPEC §9.3): what happened at the level of use, in order.
void main() {
  test('a conversation in order: the call, what its handler said and '
      'wrote, the call that answered the fact, their ends', () async {
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
      (c) {
        said.emit('!clip', cause: c.causeFor(owner));
        clipped.set('before', cause: c.causeFor(owner));
      },
    );
    r.defineCommand(
      CommandDescriptor('clip.save', callers: Callers.only(['user'])),
      (c) => clipped.set('clip-1', cause: c.causeFor(owner)),
    );
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
    final journal = <JournalEntry>[];
    r.journal.listen(journal.add);
    await r.call('chat.say', {}, by: user, id: 'start');
    await pumpEventQueue();

    String line(JournalEntry e) => switch (e) {
      JournalStart(:final call) => 'start ${call.command}',
      JournalEnd(:final call) => 'end ${call.command}',
      JournalFact(:final fact) => 'fact ${fact.fact}',
      JournalWrite(:final change) => 'write ${change.state}',
    };
    expect(journal.map(line), [
      'start chat.say',
      'fact chat.line',
      'write clip.last',
      // As it happened: the fact was answered before the call's end came.
      'start clip.save',
      'write clip.last',
      'end chat.say',
      'end clip.save',
    ]);
    expect({for (final e in journal) e.conversation}, {'start'});
    expect([for (final e in journal) e.n], [1, 2, 3, 4, 5, 6, 7]);
    expect({for (final e in journal) e.epoch}, {r.epoch});
    expect(journal.every((e) => e.trace == null), isTrue, reason: 'no log');
    await r.dispose();
  });

  test('a refusal is an end that never began; an owner\'s own write is '
      'no history', () async {
    final f = Fixture();
    final journal = <JournalEntry>[];
    f.r.journal.listen(journal.add);
    f.muted.set(true);
    await f.r.call('audio.mute', {'on': true}, by: viewer, id: 'v');
    await pumpEventQueue();
    final end = journal.single as JournalEnd;
    expect((end.call.result as CallRefused).code, Refusal.notPermitted);
    expect(end.conversation, 'v');
    await f.r.dispose();
  });

  test('each entry as one flat JSON object and back', () async {
    final f = Fixture();
    final journal = <JournalEntry>[];
    f.r.journal.listen(journal.add);
    await f.r.call('audio.mute', {'on': true}, by: user, id: 'm');
    await pumpEventQueue();
    expect(journal.map((e) => e.kind), ['start', 'write', 'end']);
    for (final e in journal) {
      final json = e.toJson();
      expect(json, containsPair('conversation', 'm'));
      expect(json['origin'], {'word': 'audio.mute', 'by': user.toJson()});
      expect(json, containsPair('kind', e.kind));
      final back = JournalEntry.fromJson(json);
      expect((back.runtimeType, back.id, back.n), (e.runtimeType, e.id, e.n));
      expect(back.cause.toJson(), e.cause.toJson());
      expect(back.toJson(), json);
    }
    expect(
      () => JournalEntry.fromJson({'epoch': 'e', 'n': 1}),
      throwsFormatException,
    );
    await f.r.dispose();
  });

  test('with spans, each entry tells the trace its telemetry is in', () async {
    final logs = LogController();
    final spans = <LogSpan>[];
    logs.stream.listen((r) {
      if (r is LogSpan) spans.add(r);
    });
    final f = Fixture(
      registry: Registry(log: logs.scope('p'), onError: (e, _) {}),
    );
    final journal = <JournalEntry>[];
    f.r.journal.listen(journal.add);
    await f.r.call('audio.mute', {'on': true}, by: user, id: 'm');
    await f.r.call('audio.mute', {'on': true}, by: viewer, id: 'v');
    await pumpEventQueue();
    final span = spans.single;
    final ofCall = journal.where((e) => e.conversation == 'm').toList();
    expect(ofCall.map((e) => e.kind), ['start', 'write', 'end']);
    for (final e in ofCall) {
      expect(e.trace, '00-${span.traceId}-${span.spanId}-01');
    }
    expect(span.data, containsPair('conversation', 'm'));
    final refused = journal.last;
    expect(refused.trace, isNull, reason: 'it followed from nothing traced');
    await f.r.dispose();
    logs.dispose();
  });

  test('nothing is made while no one listens', () async {
    final f = Fixture();
    await f.r.call('audio.mute', {'on': true}, by: user);
    final journal = <JournalEntry>[];
    f.r.journal.listen(journal.add);
    await f.r.call('audio.mute', {'on': false}, by: user);
    await pumpEventQueue();
    expect(journal.first.n, 1, reason: 'counted from the first one heard');
    await f.r.dispose();
  });
}
