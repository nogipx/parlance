import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:switchboard/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  test(
    'hooks run one by one, highest priority first, before the handler',
    () async {
      final f = Fixture();
      final order = <String>[];
      f.r.addBefore(
        'studio.show',
        'low',
        (_, _) async => order.add('low'),
        timeout: const Duration(seconds: 1),
      );
      f.r.addBefore(
        'studio.show',
        'high',
        (_, _) async => order.add('high'),
        priority: 5,
        timeout: const Duration(seconds: 1),
      );
      f.r.addBefore(
        'studio.show',
        'low2',
        (_, _) async => order.add('low2'),
        timeout: const Duration(seconds: 1),
      );
      final records = <CallRecord>[];
      f.r.calls.listen(records.add);
      await f.r.call('studio.show', {'scene': 'main'}, by: user);
      order.add('handler:${f.shown.single}');
      await pumpEventQueue();
      expect(order, ['high', 'low', 'low2', 'handler:main']);
      expect(records.single.hooks, ['high', 'low', 'low2']);
    },
  );

  test('only interceptable commands take hooks', () {
    final f = Fixture();
    expect(
      () => f.r.addBefore(
        'audio.mute',
        'x',
        (_, _) async {},
        timeout: const Duration(seconds: 1),
      ),
      throwsStateError,
    );
  });

  test("a hook's own calls are not intercepted by it", () async {
    final f = Fixture();
    const link = Principal('link', 'outro');
    f.r.addBefore('studio.show', 'outro', (c, cause) async {
      if (c.params['scene'] == 'main') {
        await f.r.call(
          'studio.show',
          {'scene': 'break'},
          by: link,
          cause: cause.withBy(link),
        );
      }
    }, timeout: const Duration(seconds: 1));
    await f.r.call('studio.show', {'scene': 'main'}, by: user);
    expect(f.shown, ['break', 'main']);
  });

  test('a hook that times out or throws is abandoned; the call goes on', () {
    fakeAsync((t) {
      final f = Fixture(
        registry: Registry(overriders: {'user'}, onError: (e, s) {}),
      );
      f.r.addBefore(
        'studio.show',
        'stuck',
        (_, _) => Completer<void>().future,
        timeout: const Duration(seconds: 2),
      );
      f.r.addBefore(
        'studio.show',
        'bad',
        (_, _) async => throw StateError('x'),
        timeout: const Duration(seconds: 2),
      );
      CallResult<Object?>? r;
      f.r.call('studio.show', {'scene': 'main'}, by: user).then((v) => r = v);
      t.elapse(const Duration(seconds: 1));
      expect(r, isNull);
      t.elapse(const Duration(seconds: 2));
      expect(r, isA<CallDone<Object?>>());
      expect(f.shown, ['main']);
    });
  });

  test(
    'hurry: the same call again from an overrider skips the rest and joins',
    () {
      fakeAsync((t) {
        final f = Fixture();
        final ran = <String>[];
        f.r.addBefore(
          'studio.show',
          'outro',
          (_, _) async {
            ran.add('outro');
            await Future<void>.delayed(const Duration(seconds: 30));
          },
          timeout: const Duration(seconds: 60),
          priority: 1,
        );
        f.r.addBefore(
          'studio.show',
          'next',
          (_, _) async => ran.add('next'),
          timeout: const Duration(seconds: 60),
        );
        CallResult<Object?>? first, second;
        f.r
            .call('studio.show', {'scene': 'main'}, by: user)
            .then((v) => first = v);
        t.elapse(const Duration(seconds: 5));
        f.r
            .call('studio.show', {'scene': 'main'}, by: user)
            .then((v) => second = v);
        t.flushMicrotasks();
        expect(first, isA<CallDone<Object?>>());
        expect(identical(first, second), isTrue);
        expect(ran, ['outro']);
        expect(f.shown, ['main'], reason: 'run once');
      });
    },
  );

  test('another principal or other params do not hurry', () {
    fakeAsync((t) {
      final f = Fixture();
      f.r.addBefore(
        'studio.show',
        'wait',
        (_, _) => Future<void>.delayed(const Duration(seconds: 10)),
        timeout: const Duration(seconds: 60),
      );
      CallResult<Object?>? a;
      f.r.call('studio.show', {'scene': 'main'}, by: user).then((v) => a = v);
      t.elapse(const Duration(seconds: 1));
      f.r.call('studio.show', {'scene': 'main'}, by: agent);
      f.r.call('studio.show', {'scene': 'break'}, by: user);
      t.elapse(const Duration(seconds: 2));
      expect(a, isNull);
      t.elapse(const Duration(seconds: 10));
      expect(a, isA<CallDone<Object?>>());
    });
  });

  test('a command removed while waiting answers unknownCommand', () {
    fakeAsync((t) {
      final r = Registry();
      final h = r.defineCommand(
        CommandDescriptor(
          'x.stop',
          callers: Callers.only(['user']),
          interceptable: true,
        ),
        (_) {},
      );
      r.addBefore(
        'x.stop',
        'wait',
        (_, _) => Future<void>.delayed(const Duration(seconds: 10)),
        timeout: const Duration(seconds: 60),
      );
      CallResult<Object?>? res;
      r.call('x.stop', {}, by: user).then((v) => res = v);
      t.elapse(const Duration(seconds: 1));
      h.dispose();
      t.flushMicrotasks();
      expect(
        res,
        isA<CallRefused>().having(
          (x) => x.code,
          'code',
          Refusal.unknownCommand,
        ),
      );
    });
  });
}
