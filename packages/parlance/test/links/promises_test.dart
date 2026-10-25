import 'dart:async';

import 'package:parlance/links.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

/// What a firing that does not run must not spend, how a press waits, who
/// may use own words, and that the engine's status and store tell the truth.
void main() {
  test(
    'a firing that does not run spends no once, no throttle, no rate',
    () async {
      final f = LinksFixture(rateLimit: 3);
      f.use([
        {
          'id': 'slow',
          'when': [
            {'manual': <String, Object?>{}},
            {'fact': 'platform.raid', 'once': true},
          ],
          'do': [
            {'wait': '80ms'},
            {
              'call': 'test.say',
              'params': {'text': 'done'},
            },
          ],
        },
      ]);
      await f.r.call('links.press', {'link': 'slow'}, by: user);
      // While it runs: five presses and a raid are turned away as running.
      for (var i = 0; i < 5; i++) {
        await f.r.call('links.press', {'link': 'slow'}, by: user);
      }
      f.raid.emit({'from': 'a', 'viewers': 1});
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(f.stateOf('slow'), LinkState.active, reason: 'not disabled');
      f.raid.emit({'from': 'b', 'viewers': 1});
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(f.said, ['done', 'done'], reason: 'the raid once was not spent');
    },
  );

  test('a queued press that waits answers when the queue is dropped', () async {
    final f = LinksFixture();
    f.use([
      {
        'id': 'q',
        'mode': 'queue',
        'when': [
          {'manual': <String, Object?>{}},
        ],
        'do': [
          {'wait': '200ms'},
        ],
      },
    ]);
    await f.r.call('links.press', {'link': 'q'}, by: user);
    final waiting = f.r.call('links.press', {
      'link': 'q',
      'wait': true,
    }, by: user);
    await pumpEventQueue();
    await f.r.call('links.stop', {'link': 'q'}, by: user);
    final r = await waiting.timeout(const Duration(seconds: 1));
    expect((r as CallDone).value, containsPair('failure', 'stopped'));
  });

  group('own words follow the managers by default', () {
    late Fixture f;
    late Links links;
    setUp(() {
      f = Fixture();
      links = Links(f.r, managers: Callers.only(['user']));
      final problems = links.apply([
        {'id': 'greet', 'command': 'greet', 'do': <Object?>[]},
        {'id': 'away', 'state': 'away'},
        {
          'id': 'open',
          'command': 'open',
          'callers': {'viewer': 'allow'},
          'do': <Object?>[],
        },
      ]);
      expect(problems, isEmpty);
    });
    tearDown(() => links.dispose());

    test('a viewer may not call them or set their state', () async {
      expect(await f.r.call('my.greet', {}, by: viewer), isA<CallRefused>());
      expect(
        await f.r.call('my.away.set', {'value': true}, by: viewer),
        isA<CallRefused>(),
      );
      expect(
        await f.r.call('my.greet', {}, by: user),
        isA<CallDone<Object?>>(),
      );
      expect(
        await f.r.call('my.away.set', {'value': true}, by: user),
        isA<CallDone<Object?>>(),
      );
    });

    test('a definition opens its own word to whom it names', () async {
      expect(
        await f.r.call('my.open', {}, by: viewer),
        isA<CallDone<Object?>>(),
      );
    });

    test('a layer still sets an own state', () async {
      f.r.pushLayer('my.away', value: true, owner: 'x', by: user);
      await pumpEventQueue();
      expect(f.r.read('my.away'), isTrue);
    });
  });

  group('a run triggered by someone outside the managers acts for them', () {
    late LinksFixture f;
    setUp(() async {
      f = LinksFixture();
      // The host's managers: everyone but viewers.
      await f.links.dispose();
      f.links2 = Links(f.r, managers: Callers.only(['user', 'link', 'plugin']));
    });
    tearDown(() => f.links2!.dispose());

    List<LinkProblem> use(Map<String, Object?> greet) => f.links2!.apply([
      greet,
      {
        'id': 'on-chat',
        'when': [
          {'fact': 'platform.chat'},
        ],
        'do': [
          {'call': 'my.greet'},
        ],
      },
    ]);

    test('a viewer\'s message cannot reach an own word by default', () async {
      expect(
        use({'id': 'greet', 'command': 'greet', 'do': <Object?>[]}),
        isEmpty,
      );
      final calls = <CallRecord>[];
      f.r.calls.listen(calls.add);
      f.chat.emit({
        'user': 'v',
        'text': 'hi',
      }, cause: const Cause(Principal('viewer', 'twitch:v')));
      await pumpEventQueue();
      final greet = calls.where((c) => c.command == 'my.greet').single;
      expect(greet.cause.by, const Principal('viewer', 'twitch:v'));
      expect(greet.result, isA<CallRefused>());
    });

    test('callers on the own word let it through', () async {
      expect(
        use({
          'id': 'greet',
          'command': 'greet',
          'callers': {'viewer': 'allow'},
          'do': <Object?>[],
        }),
        isEmpty,
      );
      final calls = <CallRecord>[];
      f.r.calls.listen(calls.add);
      f.chat.emit({
        'user': 'v',
        'text': 'hi',
      }, cause: const Cause(Principal('viewer', 'twitch:v')));
      await pumpEventQueue();
      expect(
        calls.where((c) => c.command == 'my.greet').single.result,
        isA<CallDone<Object?>>(),
      );
    });

    test('a manager\'s fact runs as the link, with no more rights', () async {
      expect(
        use({'id': 'greet', 'command': 'greet', 'do': <Object?>[]}),
        isEmpty,
      );
      final calls = <CallRecord>[];
      f.r.calls.listen(calls.add);
      f.chat.emit({'user': 'u', 'text': 'hi'}, cause: const Cause(user));
      await pumpEventQueue();
      final greet = calls.where((c) => c.command == 'my.greet').single;
      expect(greet.cause.by, linkPrincipal('on-chat'));
      expect(greet.result, isA<CallDone<Object?>>());
    });
  });

  test('a link that worked again has no old failure in its status', () async {
    final f = LinksFixture();
    var fails = true;
    f.r.defineCommand(
      CommandDescriptor('x.flaky', callers: const Callers({'*': Access.allow})),
      (_) {
        if (fails) throw StateError('not yet');
      },
    );
    f.use([
      {
        'id': 'k',
        'when': [
          {'manual': <String, Object?>{}},
        ],
        'do': [
          {'call': 'x.flaky'},
        ],
      },
    ]);
    await f.r.call('links.press', {'link': 'k', 'wait': true}, by: user);
    expect(f.links.statuses['k']!.reason, contains('not yet'));
    fails = false;
    await f.r.call('links.press', {'link': 'k', 'wait': true}, by: user);
    expect(f.links.statuses['k']!.reason, isNull);
  });

  test('a store that fails to save changes nothing', () async {
    final f = Fixture();
    final links = Links(f.r, store: _BrokenStore());
    addTearDown(links.dispose);
    final r = await f.r.call('links.upsert', {
      'link': {
        'id': 'n',
        'when': [
          {'manual': <String, Object?>{}},
        ],
        'do': <Object?>[],
      },
    }, by: user);
    expect(r, isA<CallFailed>());
    await pumpEventQueue();
    expect(f.r.read('links.own'), isEmpty);
    expect(links.links, isNot(contains('n')));
  });
}

final class _BrokenStore implements ILinksStore {
  @override
  List<Map<String, Object?>> load() => const [];

  @override
  void save(List<Map<String, Object?>> links) => throw StateError('disk full');
}
