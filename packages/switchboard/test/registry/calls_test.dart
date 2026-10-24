import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:switchboard/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

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
      await f.r.call('studio.show', {'scene': 'gone'}, by: user),
      refused(Refusal.invalidParams),
    );
    expect(
      await f.r.call('audio.mute', {'on': true}, by: viewer),
      refused(Refusal.notPermitted),
    );
    expect(
      await f.r.call('studio.show', {'scene': 'main'}, by: viewer),
      isA<CallDone>(),
      reason: 'warn allows',
    );
  });

  test('params get their defaults', () async {
    expect(
      (await f.r.call('audio.gain.set', {'input': 'mic'}, by: user)).ok,
      isTrue,
    );
    expect(f.r.read('audio.gain', key: 'mic'), 0);
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

  test('a guard denies; an overrider overrides; others cannot', () async {
    f.r.addGuard('no-test', (c) {
      if (c.command.name == 'studio.show' && c.params['scene'] == 'test') {
        return 'not on air';
      }
      return null;
    });
    final r = await f.r.call('studio.show', {'scene': 'test'}, by: user);
    expect(r, refused(Refusal.denied));
    expect((r as CallRefused).guard, 'no-test');
    expect(r.overridable, isTrue);

    final records = <CallRecord>[];
    f.r.calls.listen(records.add);
    expect(
      (await f.r.call(
        'studio.show',
        {'scene': 'test'},
        by: user,
        override: true,
      )).ok,
      isTrue,
    );
    expect(
      await f.r.call(
        'studio.show',
        {'scene': 'test'},
        by: agent,
        override: true,
      ),
      refused(Refusal.denied),
    );
    await pumpEventQueue();
    expect(records.first.overridden, ['no-test']);
  });

  test('a guard that is not overridable stays', () async {
    f.r.addGuard('hard', (_) => 'never', overridable: false);
    expect(
      await f.r.call('audio.mute', {'on': true}, by: user, override: true),
      refused(Refusal.denied),
    );
  });

  test('a throwing guard counts as no denial and goes to the sink', () async {
    final errors = <Object>[];
    final r = Registry(onError: (e, _) => errors.add(e));
    r.defineCommand(
      CommandDescriptor('x.go', callers: Callers.only(['user'])),
      (_) {},
    );
    r.addGuard('bad', (_) => throw StateError('boom'));
    expect((await r.call('x.go', {}, by: user)).ok, isTrue);
    expect(errors.single, isA<StateError>());
  });

  test(
    'a repeated id answers the first result without running again',
    () async {
      final a = f.r.call(
        'studio.show',
        {'scene': 'main'},
        by: user,
        id: 'same',
      );
      final b = f.r.call(
        'studio.show',
        {'scene': 'break'},
        by: user,
        id: 'same',
      );
      expect(await a, isA<CallDone>());
      expect(identical(await a, await b), isTrue);
      expect(f.shown, ['main']);
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
      CallResult? slow, bad, wrong;
      r.call('x.slow', {}, by: user).then((v) => slow = v);
      r.call('x.bad', {}, by: user).then((v) => bad = v);
      r.call('x.wrong', {}, by: user).then((v) => wrong = v);
      t.elapse(const Duration(seconds: 2));
      expect(slow, isA<CallTimedOut>());
      expect(bad, isA<CallFailed>());
      expect(wrong, isA<CallFailed>());
    });
  });

  test('a nested call is a child of the call that made it', () async {
    final records = <CallRecord>[];
    f.r.calls.listen(records.add);
    f.r.defineCommand(
      CommandDescriptor('x.both', callers: Callers.only(['user'])),
      (c) => f.r.call(
        'audio.mute',
        {'on': true},
        by: Principal.system,
        cause: c.causeFor(Principal.system),
      ),
    );
    await f.r.call('x.both', {}, by: user, id: 'outer');
    await pumpEventQueue();
    final inner = records.firstWhere((r) => r.command == 'audio.mute');
    expect(inner.cause.parent, 'outer');
    expect(inner.cause.by, Principal.system);
  });

  test('test marks and chains carry over to what a call causes', () async {
    final changes = <StateChange>[];
    f.r.ticks.listen((t) => changes.addAll(t.changes));
    await f.r.call(
      'audio.mute',
      {'on': true},
      by: user,
      cause: const Cause(user, chain: ['link-a'], test: true),
    );
    await pumpEventQueue();
    expect(changes.single.cause.test, isTrue);
    expect(changes.single.cause.chain, ['link-a']);
  });
}
