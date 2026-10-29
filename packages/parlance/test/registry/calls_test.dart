import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:parlance/tools.dart';
import 'package:test/test.dart';

import 'fixture.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

void main() {
  late Fixture f;

  setUp(() => f = Fixture());
  tearDown(() => f.r.dispose());

  Matcher refused(Refusal code) =>
      isA<CallRefused>().having((r) => r.code, 'code', code);

  test('the stages refuse in order', () async {
    expect(
      await f.r.call('nope', {}, by: user),
      refused(Refusal.unknownCommand),
    );
    expect(
      await f.r.call('house.show', {'room': 'gone'}, by: user),
      refused(Refusal.invalidParams),
    );
    expect(
      await f.r.call('door.lock', {'on': true}, by: visitor),
      refused(Refusal.notPermitted),
    );
    expect(
      await f.r.call('house.show', {'room': 'main'}, by: visitor),
      isA<CallDone<Object?>>(),
      reason: 'warn allows',
    );
  });

  test('params get their defaults', () async {
    expect(
      (await f.r.call('door.chime.set', {'input': 'front'}, by: user)).ok,
      isTrue,
    );
    expect(f.r.read('door.chime', key: 'front'), 0);
  });

  test('availability', () async {
    var why = 'offline';
    f.r.defineCommand(
      CommandDescriptor('x.go', callers: Callers.only(['user'])),
      (_) {},
      available: () => why.isEmpty ? null : why,
    );
    expect(await f.r.call('x.go', {}, by: user), refused(Refusal.unavailable));
    why = '';
    expect((await f.r.call('x.go', {}, by: user)).ok, isTrue);
  });

  test('a guard denies, saying which', () async {
    f.r.addGuard('no-test', (c) {
      if (c.command.name == 'house.show' && c.params['room'] == 'test') {
        return 'not on air';
      }
      return null;
    });
    final r = await f.r.call('house.show', {'room': 'test'}, by: user);
    expect(r, refused(Refusal.denied));
    expect((r as CallRefused).guard, 'no-test');
    expect(
      (await f.r.call('house.show', {'room': 'main'}, by: user)).ok,
      isTrue,
    );
  });

  test(
    'a guard that cannot judge denies, and its error goes to the sink',
    () async {
      final errors = <Object>[];
      final r = Registry(onError: (e, _) => errors.add(e));
      r.defineCommand(
        CommandDescriptor('x.go', callers: Callers.only(['user'])),
        (_) {},
      );
      r.addGuard('bad', (_) => throw StateError('boom'));
      final result = await r.call('x.go', {}, by: user);
      expect(
        result,
        isA<CallRefused>()
            .having((x) => x.code, 'code', Refusal.denied)
            .having((x) => x.guard, 'guard', 'bad'),
      );
      expect(errors.single, isA<StateError>());
    },
  );

  test(
    'a repeated id answers the first result without running again',
    () async {
      final a = f.r.call('house.show', {'room': 'main'}, by: user, id: 'same');
      final b = f.r.call('house.show', {'room': 'main'}, by: user, id: 'same');
      expect(await a, isA<CallDone<Object?>>());
      expect(identical(await a, await b), isTrue);
      expect(f.shown, ['main']);
    },
  );

  test(
    'ids are remembered as many as dedupLimit, the oldest going first',
    () async {
      final r = Registry(dedupLimit: 2);
      var ran = 0;
      r.defineCommand(
        CommandDescriptor('x.go', callers: Callers.only(['user'])),
        (_) => ran++,
      );
      for (final id in ['a', 'b', 'c']) {
        await r.call('x.go', {}, by: user, id: id);
      }
      await r.call('x.go', {}, by: user, id: 'c');
      expect(ran, 3, reason: 'c is remembered');
      await r.call('x.go', {}, by: user, id: 'a');
      expect(ran, 4, reason: 'a went past the limit: it runs again');
      await r.dispose();
    },
  );

  test('ids are forgotten after the dedup window', () {
    fakeAsync((t) {
      final r = Registry(dedupWindow: const Duration(minutes: 1));
      var runs = 0;
      r.defineCommand(
        CommandDescriptor('x.go', callers: Callers.only(['user'])),
        (_) => runs++,
      );
      r.call('x.go', {}, by: user, id: 'a');
      t.elapse(const Duration(seconds: 30));
      r.call('x.go', {}, by: user, id: 'a');
      t.elapse(const Duration(seconds: 31));
      r.call('x.go', {}, by: user, id: 'a');
      t.flushMicrotasks();
      expect(runs, 2);
    });
  });

  test('deadline, throw and a wrong answer', () {
    fakeAsync((t) {
      final r = Registry();
      r.defineCommand(
        CommandDescriptor(
          'x.slow',
          callers: Callers.only(['user']),
          deadline: const Duration(seconds: 1),
        ),
        (_) => Completer<void>().future,
      );
      r.defineCommand(
        CommandDescriptor('x.bad', callers: Callers.only(['user'])),
        (_) => throw StateError('no'),
      );
      r.defineCommand(
        CommandDescriptor(
          'x.wrong',
          callers: Callers.only(['user']),
          returns: const IntType(),
        ),
        (_) => 'text',
      );
      CallResult<Object?>? slow, bad, wrong;
      r.call('x.slow', {}, by: user).then((v) => slow = v);
      r.call('x.bad', {}, by: user).then((v) => bad = v);
      r.call('x.wrong', {}, by: user).then((v) => wrong = v);
      t.elapse(const Duration(seconds: 2));
      expect(slow, isA<CallTimedOut>());
      expect(bad, isA<CallFailed>());
      expect(wrong, isA<CallFailed>());
    });
  });

  test('a call is told as its handler begins, and runs until it ends, past '
      'its deadline too; a refused call or a query never begins', () {
    fakeAsync((t) {
      final r = Registry();
      final slow = Completer<void>();
      r.defineCommand(
        CommandDescriptor(
          'x.slow',
          callers: Callers.only(['user']),
          deadline: const Duration(seconds: 1),
        ),
        (_) => slow.future,
      );
      r.defineQuery(
        QueryDescriptor(
          'x.ask',
          returns: const IntType(),
          askers: Callers.only(['user']),
        ),
        (_) => 1,
      );
      final starts = <CallStarted>[];
      final ends = <CallRecord>[];
      r.callStarts.listen(starts.add);
      r.calls.listen(ends.add);
      r.call('x.slow', {}, by: user, id: 'a');
      r.call('x.slow', {}, by: agent);
      r.call('x.ask', {}, by: user);
      t.flushMicrotasks();
      expect([for (final s in starts) s.id], ['a']);
      expect(starts.single.cause.by, user);
      expect([for (final c in r.running) c.id], ['a']);
      t.elapse(const Duration(seconds: 2));
      expect(ends.last.result, isA<CallTimedOut>());
      expect(r.running, hasLength(1), reason: 'its handler goes on');
      slow.complete();
      t.flushMicrotasks();
      expect(r.running, isEmpty);
      expect(ends.last.late, isTrue);
    });
  });

  test('timedOut is no end: the handler is told, its end is recorded late, '
      'a retry with the id answers it', () {
    fakeAsync((t) {
      final r = Registry();
      final w = r.defineState(
        StateDescriptor('x.done', type: const BoolType()),
        by: owner,
      );
      var told = false;
      r.defineCommand(
        CommandDescriptor(
          'x.slow',
          callers: Callers.only(['user']),
          deadline: const Duration(seconds: 1),
        ),
        (c) async {
          unawaited(c.expired.then((_) => told = true));
          await Future<void>.delayed(const Duration(seconds: 3));
          w.set(true, cause: c.causeFor(owner));
        },
      );
      final records = <CallRecord>[];
      r.calls.listen(records.add);
      CallResult<Object?>? first, again;
      r.call('x.slow', {}, by: user, id: 's').then((v) => first = v);
      t.elapse(const Duration(seconds: 2));
      expect(first, isA<CallTimedOut>());
      expect(told, isTrue);
      expect(r.read('x.done'), isNull);
      t.elapse(const Duration(seconds: 2));
      expect(r.read('x.done'), isTrue, reason: 'what it did stands');
      expect(records.last.late, isTrue);
      expect(records.last.result, isA<CallDone<Object?>>());
      expect(r.callRecord('s')!.late, isTrue);
      r.call('x.slow', {}, by: user, id: 's').then((v) => again = v);
      t.flushMicrotasks();
      expect(again, isA<CallDone<Object?>>());
    });
  });

  test('explain says when the change may be forgotten', () async {
    final r = Registry(retainTicks: 2);
    final a = r.defineState(
      StateDescriptor('x.a', type: const IntType()),
      by: owner,
    );
    final b = r.defineState(
      StateDescriptor('x.b', type: const IntType()),
      by: owner,
    );
    a.set(1);
    expect(r.explain('x.a').forgotten, isFalse);
    b.set(1);
    b.set(2);
    b.set(3);
    final e = r.explain('x.a');
    expect(e.change, isNull);
    expect(e.forgotten, isTrue);
    expect(Explanation.fromJson(e.toJson()).forgotten, isTrue);
  });

  test(
    'an id is the call it was given for: another call with it is refused',
    () async {
      final first = await f.r.call(
        'door.lock',
        {'on': true},
        by: user,
        id: 'x',
      );
      expect(first, isA<CallDone<Object?>>());
      expect(
        await f.r.call('door.lock', {'on': true}, by: user, id: 'x'),
        isA<CallDone<Object?>>(),
        reason: 'the same call answers the first result',
      );
      for (final other in [
        f.r.call('door.lock', {'on': false}, by: user, id: 'x'),
        f.r.call('house.show', {'room': 'break'}, by: user, id: 'x'),
        f.r.call('door.lock', {'on': true}, by: agent, id: 'x'),
      ]) {
        final r = await other;
        expect(r, isA<CallRefused>());
        expect((r as CallRefused).code, Refusal.idConflict);
      }
      expect(f.shown, isEmpty);
    },
  );

  test('a nested call is a child of the call that made it', () async {
    final records = <CallRecord>[];
    f.r.calls.listen(records.add);
    f.r.defineCommand(
      CommandDescriptor('x.both', callers: Callers.only(['user'])),
      (c) => f.r.call(
        'door.lock',
        {'on': true},
        by: Principal.system,
        cause: c.causeFor(Principal.system),
      ),
    );
    await f.r.call('x.both', {}, by: user, id: 'outer');
    await pumpEventQueue();
    final inner = records.firstWhere((r) => r.command == 'door.lock');
    expect(inner.cause.parent, 'outer');
    expect(inner.cause.by, Principal.system);
  });

  test('a command gone while its guard was asked answers unknownCommand', () {
    fakeAsync((t) {
      final r = Registry();
      final served = r.defineCommand(
        CommandDescriptor('x.go', callers: Callers.only(['user'])),
        (_) {},
      );
      r.addAskedGuard(
        'far',
        (_) => Future.delayed(const Duration(seconds: 1), () => null),
      );
      CallResult<Object?>? result;
      r.call('x.go', {}, by: user).then((x) => result = x);
      t.flushMicrotasks();
      served.dispose();
      t.elapse(const Duration(seconds: 1));
      expect(result, refused(Refusal.unknownCommand));
    });
  });

  test('whyUnavailable tells without calling', () {
    var why = 'offline';
    f.r.defineCommand(
      CommandDescriptor('x.go', callers: Callers.only(['user'])),
      (_) {},
      available: () => why.isEmpty ? null : why,
    );
    expect(f.r.whyUnavailable('x.go'), 'offline');
    why = '';
    expect(f.r.whyUnavailable('x.go'), isNull);
    expect(f.r.whyUnavailable('nope'), 'no command nope');
  });

  test('a result says why not in words, and nothing when done', () async {
    expect(
      (await f.r.call('door.lock', {'on': true}, by: user)).whyNot,
      isNull,
    );
    expect(
      (await f.r.call('door.lock', {'on': true}, by: visitor)).whyNot,
      contains('may not call door.lock'),
    );
    expect(const CallFailed('disk full').whyNot, 'disk full');
    expect(const CallTimedOut().whyNot, contains('may still happen'));
    expect(const CallLost('c1', 'socket closed').whyNot, contains('retry'));
  });
}
