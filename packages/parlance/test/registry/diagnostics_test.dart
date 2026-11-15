import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/testing.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/messages.dart' show Kept;
import 'package:parlance/src/registry/registry.dart'
    show RawRegistry, RegistryStreams;
import 'package:test/test.dart';

void main() {
  for (final sinkAcross in [false, true]) {
    for (final across in [false, true]) {
      test(
        'completed handler remains a verified parent, across=$across, sinkAcross=$sinkAcross',
        () async {
          final host = TestHost();
          addTearDown(host.dispose);
          final worker = across
              ? await host.join(
                  const Principal('worker'),
                  vocabularies: [const WordSet.open('worker')],
                )
              : host.participant(
                  const Principal('worker'),
                  vocabularies: [const WordSet.open('worker')],
                );
          final sink = sinkAcross
              ? await host.join(
                  const Principal('sink'),
                  vocabularies: [const WordSet.open('sink')],
                )
              : host.participant(
                  const Principal('sink'),
                  vocabularies: [const WordSet.open('sink')],
                );
          final causes = <Cause>[];
          final receivedIds = <String>[];
          final received = Completer<void>();
          sink.raw.defineCommand(
            CommandDescriptor('sink.record', callers: Callers.anyone),
            (c) {
              causes.add(c.cause);
              receivedIds.add(c.id);
              if (!received.isCompleted) received.complete();
            },
          );
          final value = worker.raw.defineState(
            StateDescriptor('worker.value', type: const IntType()),
          );
          final release = Completer<void>();
          worker.raw.defineCommand(
            CommandDescriptor('worker.start', callers: Callers.anyone),
            (_) {
              value.set(1);
              unawaited(
                release.future.then((_) async {
                  await worker.raw.call('sink/sink.record', {});
                }),
              );
            },
          );
          await worker.settle();
          await sink.settle();
          await host
              .participant(const Principal('user'))
              .raw
              .call('worker/worker.start', {}, id: 'root');
          release.complete();
          await received.future;
          expect(causes.single.parent, 'user#root');
          expect(causes.single.origin!.word, 'worker/worker.start');
          final change = host.registry.lastChange('worker/worker.value')!;
          await worker.raw.call(
            'sink/sink.record',
            {},
            cause: change.cause.child(
              change.id,
              by: worker.who,
              word: change.state,
            ),
          );
          expect(causes.last.parent, change.id);
          expect(causes.last.conversation, 'user#root');
          expect(causes.last.origin, causes.first.origin);
          final inspected = await sink.raw.inspectCall(receivedIds.last);
          expect(((inspected['trail'] as List).first as Map)['kind'], 'write');
          expect(((inspected['trail'] as List).last as Map)['kind'], 'end');
        },
      );
    }
  }

  test(
    'explain follows active calls, facts and streams without duplicating payload history',
    () async {
      final r = Registry();
      addTearDown(r.dispose);
      const who = Principal('house');
      final state = r.defineState(
        StateDescriptor('house.value', type: const IntType()),
        by: who,
      );
      final release = Completer<void>();
      r.defineCommand(
        CommandDescriptor('house.slow', callers: Callers.anyone),
        (c) {
          state.set(1, cause: c.causeFor(who));
          return release.future;
        },
      );
      final slow = r.call('house.slow', {}, by: who, id: 'slow');
      expect(r.explain('house.value').trail.single, isA<JournalStart>());
      release.complete();
      await slow;
      final fact = r.defineFact(
        FactDescriptor('house.changed', type: const IntType()),
        by: who,
      );
      fact.say(2, id: 'fact', cause: const Cause(who));
      final said = r.recent('house.changed', 1).single;
      state.set(
        2,
        cause: said.cause.child(said.id, by: who, word: said.fact),
      );
      expect(r.explain('house.value').trail.single, isA<JournalFact>());
      r.defineStream(
        ServerStreamDescriptor('house.values', type: const IntType()),
        (c) {
          state.set(
            3,
            cause: c.cause.child(c.id, by: who, word: c.word),
          );
          return Stream.value(3);
        },
      );
      await r
          .openStream(
            'house.values',
            Kept.json({}),
            const PlainShape<int>(IntType()),
            by: who,
          )
          .toList();
      final explanation = r.explain('house.value');
      expect(
        (explanation.trail.single as JournalDiagnostic).event,
        'stream.closed',
      );
      expect(explanation.gap, isNull);
      expect(
        Explanation.fromJson(explanation.toJson()).trail.single.word,
        'house.values',
      );
    },
  );

  test('timeout retains the caller reply alongside late completion', () async {
    final r = Registry();
    addTearDown(r.dispose);
    final release = Completer<void>();
    r.defineCommand(
      CommandDescriptor(
        'house.slow',
        callers: Callers.anyone,
        deadline: const Duration(milliseconds: 1),
      ),
      (_) => release.future,
    );
    expect(
      await r.call('house.slow', {}, by: const Principal('user'), id: 'late'),
      isA<CallTimedOut>(),
    );
    release.complete();
    await Future<void>.delayed(Duration.zero);
    final record = r.callRecord('late')!;
    expect(record.result, isA<CallDone<Object?>>());
    expect(record.replyResult, isA<CallTimedOut>());
    expect(
      record.repliedAt!.isBefore(record.finished) ||
          record.repliedAt == record.finished,
      isTrue,
    );
    expect(
      CallRecord.fromJson(record.toJson()).replyResult,
      isA<CallTimedOut>(),
    );
  });

  test(
    'guard waits and retries are visible and metadata retention is bounded',
    () async {
      final r = Registry(
        limits: const HostLimits(retainTicks: 4, retainBytes: 2048),
      );
      addTearDown(r.dispose);
      final gate = Completer<String?>();
      r.defineCommand(
        CommandDescriptor('house.run', callers: Callers.anyone),
        (_) {},
      );
      final guard = r.addAskedGuard('check', (_) => gate.future);
      final call = r.call(
        'house.run',
        {},
        by: const Principal('user'),
        id: 'one',
      );
      expect(r.pending.single.event, 'guard.waiting');
      expect(r.pending.single.id, 'one');
      gate.complete(null);
      await call;
      expect(r.pending, isEmpty);
      guard.dispose();
      await r.call('house.run', {}, by: const Principal('user'), id: 'one');
      expect(r.diagnostics.last.event, 'reused');
      for (var i = 0; i < 100; i++) {
        await r.call('house.run', {}, by: const Principal('user'));
      }
      expect(r.diagnostics.length, lessThanOrEqualTo(4));
      expect(
        r.diagnostics.fold<int>(0, (n, e) => n + e.retainedBytes),
        lessThanOrEqualTo(2048),
      );
      await r.dispose();
      expect(r.diagnostics, isEmpty);
      expect(r.pending, isEmpty);
      expect(r.running, isEmpty);
      expect(r.callRecord('one'), isNull);
    },
  );

  test(
    'admission evidence records the effective rule and its host revision',
    () async {
      final host = Host();
      addTearDown(host.dispose);
      final owner = host.participant(
        const Principal('house'),
        vocabularies: [const WordSet.open('house')],
      );
      owner.raw.defineCommand(
        CommandDescriptor('house.run', callers: Callers.anyone),
        (_) {},
      );
      final caller = host.participant(const Principal('user'));
      await caller.raw.call('house/house.run', {}, id: 'allowed');
      final allowed = host.registry.diagnostics.lastWhere(
        (d) => d.event == 'access.allowed',
      );
      expect(allowed.data['source'], 'declaration');
      expect(allowed.data['selector'], '*');
      host.setAccess(
        address: WordAddress(owner.who, 'house.run'),
        access: const WordAccess(callers: Callers({'user': Access.deny})),
      );
      await caller.raw.call('house/house.run', {}, id: 'denied');
      final refused = host.registry.diagnostics.lastWhere(
        (d) => d.event == 'refused',
      );
      expect(refused.data['source'], 'host');
      expect(refused.data['revision'], 1);
      expect(refused.data['selector'], 'user');
      expect(refused.data['access'], 'deny');
    },
  );

  test('light hosts keep no added diagnostic history', () async {
    final r = Registry(limits: HostLimits.light);
    addTearDown(r.dispose);
    r.defineCommand(
      CommandDescriptor('house.run', callers: Callers.anyone),
      (_) {},
    );
    await r.call('house.run', {}, by: const Principal('user'));
    expect(r.diagnostics, isEmpty);
    expect(r.pending, isEmpty);
  });

  test(
    'participant explanation does not expose a restricted ancestor payload',
    () async {
      final host = Host();
      addTearDown(host.dispose);
      final owner = host
          .participant(
            const Principal('house'),
            vocabularies: [const WordSet.open('house')],
          )
          .raw;
      final fact = owner.defineFact(
        FactDescriptor(
          'house.secret',
          type: const TextType(),
          readers: Callers.only(['house']),
        ),
      );
      final state = owner.defineState(
        StateDescriptor('house.public', type: const BoolType()),
      );
      fact.say('private');
      final said = host.registry.recent('house/house.secret', 1).single;
      state.set(
        true,
        cause: said.cause.child(said.id, by: owner.who, word: said.fact),
      );
      final explanation = await host
          .participant(const Principal('reader'))
          .raw
          .explain('house/house.public');
      expect(explanation.trail.single.payloads, isFalse);
      expect((explanation.trail.single as JournalFact).fact.payload, isNull);
      expect(
        host.registry.explain('house/house.public').trail.single.payloads,
        isTrue,
      );
    },
  );
  test('pre-handler callback failures release pending diagnostics', () async {
    final r = Registry();
    addTearDown(r.dispose);
    r.defineCommand(
      CommandDescriptor('house.run', callers: Callers.anyone),
      (_) {},
      whyNot: () => throw StateError('availability failed'),
    );
    await expectLater(
      r.call('house.run', {}, by: const Principal('user')),
      throwsStateError,
    );
    expect(r.pending, isEmpty);
  });

  test(
    'a reused ID after dedup eviction cannot claim unique ancestry',
    () async {
      final r = Registry(limits: const HostLimits(dedupLimit: 1));
      addTearDown(r.dispose);
      r.defineCommand(
        CommandDescriptor('house.run', callers: Callers.anyone),
        (_) {},
      );
      for (final id in ['same', 'other', 'same']) {
        await r.call('house.run', {}, by: const Principal('user'), id: id);
      }
      expect(r.callRecord('same')!.ambiguous, isTrue);
      expect((r.message('same') as JournalDiagnostic).event, 'id.ambiguous');
      final cause = r.causeFrom('same', const Principal('house'), served: true);
      expect(cause.parent, isNull);
      expect(cause.unresolvedParent, 'same');
    },
  );

  test(
    'selected independent writes and reentrant overflow report coverage gaps',
    () async {
      final r = Registry();
      addTearDown(r.dispose);
      final state = r.defineState(
        StateDescriptor('house.value', type: const IntType()),
        by: const Principal('house'),
      );
      final capture = r.captureStateWrites(['house.value']);
      final entries = <JournalEntry>[];
      var nested = false;
      final sub = r.journal.listen((e) {
        entries.add(e);
        if (!nested) {
          nested = true;
          for (var i = 0; i < 100; i++) {
            state.set(i);
          }
        }
      });
      addTearDown(sub.cancel);
      r.defineFact(
        FactDescriptor('house.changed', type: const IntType()),
        by: const Principal('house'),
      );
      expect(entries.whereType<JournalWrite>(), hasLength(64));
      expect(entries.whereType<JournalDiagnostic>().last.event, 'capture.gap');
      capture.dispose();
      final length = entries.length;
      state.set(101);
      expect(entries, hasLength(length));
    },
  );

  test(
    'RPC preserves unverified parent evidence without accepting its origin',
    () async {
      final host = TestHost();
      addTearDown(host.dispose);
      final owner = host.participant(
        const Principal('house'),
        vocabularies: [const WordSet.open('house')],
      );
      final caller = await host.join(const Principal('caller'));
      Cause? received;
      owner.raw.defineCommand(
        CommandDescriptor('house.run', callers: Callers.anyone),
        (c) {
          received = c.cause;
        },
      );
      await caller.raw.call(
        'house/house.run',
        {},
        id: 'unverified',
        cause: const Cause(
          Principal('caller'),
          parent: 'missing',
          origin: Origin('forged.start', Principal('forged')),
        ),
      );
      expect(received!.parent, isNull);
      expect(received!.unresolvedParent, 'missing');
      expect(received!.origin?.word, isNot('forged.start'));
      expect(
        (await caller.raw.inspectCall('unverified'))['gap'],
        contains('missing'),
      );
    },
  );

  test(
    'host disposal releases a paused journal backlog and reports the gap',
    () async {
      final r = Registry();
      final entries = <JournalEntry>[];
      final errors = <Object>[];
      final done = Completer<void>();
      final sub = r.journal.listen(
        entries.add,
        onError: (Object e) => errors.add(e),
        onDone: done.complete,
      );
      addTearDown(sub.cancel);
      sub.pause();
      r.defineFact(
        FactDescriptor('house.changed', type: const IntType()),
        by: const Principal('house'),
      );
      await r.dispose().timeout(const Duration(seconds: 1));
      sub.resume();
      await done.future;
      expect(entries, isEmpty);
      expect((errors.single as StreamFailure).message, contains('discarded'));
    },
  );

  test(
    'paused journal subscriptions terminate rather than retaining an unbounded backlog',
    () async {
      final r = Registry();
      addTearDown(r.dispose);
      final errors = <Object>[];
      final done = Completer<void>();
      final sub = r.journal.listen(
        (_) {},
        onError: (Object e) => errors.add(e),
        onDone: done.complete,
      );
      sub.pause();
      r.defineCommand(
        CommandDescriptor('house.run', callers: Callers.anyone),
        (_) {},
      );
      for (var i = 0; i < 100; i++) {
        await r.call('house.run', {}, by: const Principal('user'));
      }
      sub.resume();
      await done.future;
      expect(errors.single, isA<StreamFailure>());
      await sub.cancel();
    },
  );

  for (final across in [false, true]) {
    test(
      'call inspection and requested state history work across=$across',
      () async {
        final host = TestHost();
        addTearDown(host.dispose);
        final owner = host.participant(
          const Principal('house'),
          vocabularies: [const WordSet.open('house')],
        );
        final reader = across
            ? await host.join(const Principal('user'))
            : host.participant(const Principal('user'));
        final state = owner.raw.defineState(
          StateDescriptor('house.state', type: const IntType()),
        );
        final release = Completer<void>();
        owner.raw.defineCommand(
          CommandDescriptor('house.run', callers: Callers.anyone),
          (_) => release.future,
        );
        state.set(1);
        state.set(2);
        final call = reader.raw.call('house/house.run', {}, id: 'inspect');
        // The same completion barrier works for the RPC transport as well.
        for (var i = 0; i < 100 && host.registry.running.isEmpty; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        final inspection = await reader.raw.inspectCall('inspect');
        expect(inspection['running'], isTrue);
        final explanation = await reader.raw.explain(
          'house/house.state',
          historyCount: 2,
        );
        expect(explanation.history.map((c) => c.value), [1, 2]);
        await expectLater(
          host
              .participant(const Principal('other'))
              .raw
              .inspectCall('user#inspect'),
          throwsA(isA<NotPermitted>()),
        );
        release.complete();
        await call;
      },
    );
  }
}
