import 'package:fake_async/fake_async.dart';
import 'package:switchboard/links.dart';
import 'package:switchboard/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  late LinksFixture f;
  setUp(() => f = LinksFixture());

  group('bindings', () {
    final breakHolds = {
      'id': 'break',
      'while': [
        {'state': 'studio.program', 'is': 'break'},
      ],
      'hold': [
        {
          'call': 'audio.mute',
          'params': {'on': true},
        },
        {
          'call': 'audio.gain.set',
          'params': {'input': 'music', 'db': -12},
        },
      ],
    };

    test('hold while the condition is true, let go after', () async {
      f.muted.set(false);
      f.gain.set(-20, key: 'music');
      f.use([breakHolds]);
      f.program.set('break');
      await pumpEventQueue();
      expect(f.r.read('audio.muted'), true);
      expect(f.r.read('audio.gain', key: 'music'), -12);
      f.program.set('main');
      await pumpEventQueue();
      expect(f.r.read('audio.muted'), false);
      expect(f.r.read('audio.gain', key: 'music'), -20);
    });

    test(
      'a human override is not undone until the condition comes again',
      () async {
        f.muted.set(false);
        f.use([breakHolds]);
        f.program.set('break');
        await pumpEventQueue();
        await f.r.call('audio.mute', {'on': false}, by: user);
        await pumpEventQueue();
        f.gain.set(-5, key: 'mic');
        await pumpEventQueue();
        expect(f.r.read('audio.muted'), false, reason: 'not pushed again');
        f.program.set('main');
        await pumpEventQueue();
        expect(
          f.r.read('audio.muted'),
          false,
          reason: 'the base is the override',
        );
        f.program.set('break');
        await pumpEventQueue();
        expect(f.r.read('audio.muted'), true);
      },
    );

    test('a binding changed while it holds moves its value straight to the '
        'new one', () async {
      f.muted.set(false);
      f.gain.set(-20, key: 'music');
      f.use([breakHolds]);
      f.program.set('break');
      await pumpEventQueue();
      final written = <Object?>[];
      final sub = f.r.watch('audio.gain', key: 'music').listen(written.add);
      f.use([
        {
          ...breakHolds,
          'hold': [
            {
              'call': 'audio.gain.set',
              'params': {'input': 'music', 'db': -6},
            },
          ],
        },
      ]);
      await pumpEventQueue();
      expect(f.r.read('audio.gain', key: 'music'), -6);
      expect(written, isNot(contains(-20)), reason: 'not through the base');
      expect(f.r.read('audio.muted'), false, reason: 'no longer held');
      f.program.set('main');
      await pumpEventQueue();
      expect(f.r.read('audio.gain', key: 'music'), -20);
      await sub.cancel();
    });

    test('after a restart, a binding takes its layers back, the base under '
        'them kept', () async {
      f.muted.set(false);
      f.use([breakHolds]);
      f.program.set('break');
      await pumpEventQueue();
      final kept = f.r.exportLayers();
      // Started again on Break, with the held value kept as it was.
      Future<LinksFixture> restart(String scene) async {
        final g = LinksFixture();
        addTearDown(g.r.dispose);
        g.muted.set(true);
        g.program.set(scene);
        g.r.importLayers(kept);
        g.use([breakHolds]);
        await pumpEventQueue();
        return g;
      }

      final again = await restart('break');
      expect(again.r.read('audio.muted'), true);
      again.program.set('main');
      await pumpEventQueue();
      expect(
        again.r.read('audio.muted'),
        false,
        reason: 'the base from before',
      );
      // Started on another scene: let go at once, not after the grace.
      final away = await restart('main');
      expect(away.r.read('audio.muted'), false);
      expect(away.r.layers(), isEmpty);
      // Links started before the layers came: they take them back.
      final late = LinksFixture();
      addTearDown(late.r.dispose);
      late.program.set('main');
      late.muted.set(false);
      late.use([breakHolds]);
      late.muted.set(true);
      late.r.importLayers(kept);
      late.links.takeBackLayers();
      await pumpEventQueue();
      expect(late.r.read('audio.muted'), false);
      expect(late.r.layers(), isEmpty);
    });

    test('an anchor gives the condition and the home', () async {
      f.links.registerAnchor(
        AnchorKind(
          'scene',
          entityKind: 'scene',
          condition: (id) =>
              StateIs('studio.program', null, ValueTest(Op.isEqual, id)),
        ),
      );
      f.muted.set(false);
      f.use([
        {
          'id': 'break-sound',
          'anchor': {'scene': 'break'},
          'hold': [
            {
              'call': 'audio.mute',
              'params': {'on': true},
            },
          ],
        },
        {
          'id': 'gone-scene',
          'anchor': {'scene': 'nowhere'},
          'hold': [
            {
              'call': 'audio.mute',
              'params': {'on': true},
            },
          ],
        },
      ]);
      expect(f.stateOf('gone-scene'), LinkState.unresolved);
      f.program.set('break');
      await pumpEventQueue();
      expect(f.r.read('audio.muted'), true);
    });

    test('two bindings: priority decides', () async {
      f.gain.set(0, key: 'music');
      f.use([
        {
          'id': 'low',
          'while': [
            {'state': 'audio.muted', 'is': true},
          ],
          'hold': [
            {
              'call': 'audio.gain.set',
              'params': {'input': 'music', 'db': -10},
            },
          ],
        },
        {
          'id': 'high',
          'priority': 5,
          'while': [
            {'state': 'audio.muted', 'is': true},
          ],
          'hold': [
            {
              'call': 'audio.gain.set',
              'params': {'input': 'music', 'db': -30},
            },
          ],
        },
      ]);
      f.muted.set(true);
      await pumpEventQueue();
      expect(f.r.read('audio.gain', key: 'music'), -30);
    });
  });

  group('constraints', () {
    test('deny a command with params while a condition holds', () async {
      f.use([
        {
          'id': 'no-test',
          'deny': {
            'command': 'studio.show',
            'where': {'scene': 'test'},
          },
          'while': [
            {'state': 'audio.muted', 'is': false},
          ],
          'reason': 'Test is not for the air',
        },
      ]);
      f.muted.set(false);
      final r = await f.r.call('studio.show', {'scene': 'test'}, by: user);
      expect(
        r,
        isA<CallRefused>()
            .having((x) => x.guard, 'guard', 'no-test')
            .having((x) => x.reason, 'reason', 'Test is not for the air'),
      );
      expect(
        (await f.r.call('studio.show', {'scene': 'main'}, by: user)).ok,
        isTrue,
      );
      expect(
        (await f.r.call(
          'studio.show',
          {'scene': 'test'},
          by: user,
          override: true,
        )).ok,
        isTrue,
      );
      f.muted.set(true);
      expect(
        (await f.r.call('studio.show', {'scene': 'test'}, by: agent)).ok,
        isTrue,
      );
      final tried = await f.r.call('links.try', {'link': 'no-test'}, by: user);
      expect((tried as CallDone).value, {'denies': false});
    });

    test('deny everything for some callers, a namespace for all', () async {
      f.use([
        {
          'id': 'quiet-viewers',
          'deny': <String, Object?>{},
          'callers': ['viewer'],
          'reason': 'focus',
        },
        {
          'id': 'no-audio',
          'deny': {'namespace': 'audio'},
          'reason': 'locked',
          'overridable': false,
        },
      ]);
      expect(
        (await f.r.call('studio.show', {'scene': 'main'}, by: viewer)).ok,
        isFalse,
      );
      expect(
        (await f.r.call('studio.show', {'scene': 'main'}, by: user)).ok,
        isTrue,
      );
      expect(
        (await f.r.call(
          'audio.mute',
          {'on': true},
          by: user,
          override: true,
        )).ok,
        isFalse,
      );
    });
  });

  group('interceptions', () {
    test('steps run before the command, whoever calls it', () async {
      f.use([
        {
          'id': 'outro',
          'before': {'command': 'studio.show'},
          'do': [
            {
              'call': 'test.say',
              'params': {'text': r'before {params.scene}'},
            },
          ],
          'timeout': '1m',
        },
      ]);
      await f.r.call('studio.show', {'scene': 'main'}, by: agent);
      expect(f.said, ['before main']);
      expect(f.shown, ['main']);
    });

    test('a slow interception is cut at its timeout', () {
      fakeAsync((t) {
        final x = LinksFixture();
        x.use([
          {
            'id': 'slow',
            'before': {'command': 'studio.show'},
            'do': [
              {'wait': '5m'},
            ],
            'timeout': '30s',
          },
        ]);
        CallResult<Object?>? r;
        x.r.call('studio.show', {'scene': 'main'}, by: user).then((v) => r = v);
        t.elapse(const Duration(seconds: 31));
        expect(r, isA<CallDone<Object?>>());
      });
    });

    test('a command that is not interceptable makes the link invalid', () {
      f.use([
        {
          'id': 'bad',
          'before': {'command': 'audio.mute'},
          'do': <Object?>[],
          'timeout': '1s',
        },
      ]);
      expect(f.stateOf('bad'), LinkState.invalid);
    });
  });

  group('own words', () {
    test(
      'an own state with a default, a setter, a flip from a button',
      () async {
        f.use([
          {'id': 'focus', 'state': 'focus'},
          {
            'id': 'focus-button',
            'when': [
              {
                'manual': {'label': 'Focus'},
              },
            ],
            'do': [
              {'flip': 'my.focus'},
            ],
          },
          {
            'id': 'focus-quiet',
            'deny': <String, Object?>{},
            'callers': ['viewer'],
            'while': [
              {'state': 'my.focus', 'is': true},
            ],
            'reason': 'in focus',
          },
        ]);
        expect(f.r.read('my.focus'), false);
        expect(f.stateOf('focus-quiet'), LinkState.active);
        await f.r.call('links.press', {'link': 'focus-button'}, by: user);
        await pumpEventQueue();
        expect(f.r.read('my.focus'), true);
        expect(
          (await f.r.call('studio.show', {'scene': 'main'}, by: viewer)).ok,
          isFalse,
        );
        expect(f.links.exportOwnStates(), {'my.focus': true});
      },
    );

    test('own state values come back in a new engine', () async {
      final x = LinksFixture();
      await x.links.dispose();
      final l = Links(x.r, ownStates: {'my.mode': 'talk'});
      l.apply([
        {
          'id': 'mode',
          'state': 'mode',
          'values': ['game', 'talk'],
        },
      ]);
      expect(x.r.read('my.mode'), 'talk');
    });

    test('an own command runs its steps with its params', () async {
      f.use([
        {
          'id': 'brb',
          'command': 'brb',
          'params': {
            'minutes': {'type': 'int', 'min': 1, 'default': 10},
          },
          'do': [
            {
              'call': 'studio.show',
              'params': {'scene': 'break'},
            },
            {
              'call': 'test.say',
              'params': {'text': 'back in {minutes}'},
            },
          ],
        },
        {
          'id': 'mod-brb',
          'when': [
            {
              'fact': 'platform.chat',
              'where': {'text': '!brb'},
            },
          ],
          'do': [
            {'call': 'my.brb'},
          ],
        },
      ]);
      expect((await f.r.call('my.brb', {'minutes': 5}, by: user)).ok, isTrue);
      expect(f.said, ['back in 5']);
      f.chat.emit({'user': 'mod', 'text': '!brb'});
      await pumpEventQueue();
      expect(f.said, ['back in 5', 'back in 10']);
    });

    test('an own command that calls itself fails', () async {
      f.use([
        {
          'id': 'again',
          'command': 'again',
          'do': [
            {'call': 'my.again'},
          ],
        },
      ]);
      expect(await f.r.call('my.again', {}, by: user), isA<CallFailed>());
    });
  });

  group('resolution', () {
    test('a link naming what is not there waits for it', () async {
      f.use([
        {
          'id': 'later',
          'when': [
            {'fact': 'plugin.thing'},
          ],
          'do': [
            {
              'call': 'test.say',
              'params': {'text': 'thing'},
            },
          ],
        },
      ]);
      expect(f.links.statuses['later']!.missing, ['plugin.thing']);
      final thing = f.r.defineFact(
        FactDescriptor('plugin.thing', type: const AnyType()),
        by: owner,
      );
      await pumpEventQueue();
      expect(f.stateOf('later'), LinkState.active);
      thing.emit(null);
      await pumpEventQueue();
      expect(f.said, ['thing']);
      thing.dispose();
      await pumpEventQueue();
      expect(f.stateOf('later'), LinkState.unresolved);
    });

    test('bad definitions are problems; the rest is taken', () {
      final problems = f.links.apply([
        {'id': 'ok', 'state': 'flag'},
        {
          'id': 'bad',
          'when': [
            {'fact': 'NotAName'},
          ],
          'do': <Object?>[],
        },
        {'id': 'ok', 'state': 'flag2'},
        {'nothing': true},
      ]);
      expect(problems.map((p) => p.id), ['bad', 'ok', null]);
      expect(f.stateOf('bad'), LinkState.invalid);
      expect(f.r.read('my.flag'), false);
    });

    test('apply replaces the set: gone links stop, same ones go on', () async {
      f.muted.set(false);
      final binding = {
        'id': 'b',
        'while': [
          {'state': 'studio.program', 'is': 'break'},
        ],
        'hold': [
          {
            'call': 'audio.mute',
            'params': {'on': true},
          },
        ],
      };
      f.use([binding]);
      f.program.set('break');
      await pumpEventQueue();
      expect(f.r.read('audio.muted'), true);
      f.use([binding]);
      await pumpEventQueue();
      expect(f.r.read('audio.muted'), true);
      f.use([]);
      await pumpEventQueue();
      expect(f.r.read('audio.muted'), false);
      expect(f.links.statuses, isEmpty);
    });
  });

  group('trigger extensions', () {
    setUp(() {
      f.links.registerTrigger(
        TriggerExtension(
          'chat',
          translate: (o) => const FactTrigger('platform.chat', Filter({})),
          accept: (data, o) {
            final m = data as Map;
            final text = m['text'] as String;
            final name = o['chat'] as String;
            if (text != name && !text.startsWith('$name ')) return null;
            final rest = text.substring(name.length).trim();
            return (
              data: {...m, 'args': rest.isEmpty ? <String>[] : rest.split(' ')},
              by: Principal('viewer', m['user'] as String),
            );
          },
        ),
      );
      f.links.registerTrigger(
        TriggerExtension(
          'button',
          translate: (o) => ManualTrigger((o['button'] as Map).cast()),
        ),
      );
    });

    test('a chat command runs on behalf of the viewer, throttled', () {
      fakeAsync((t) {
        final x = LinksFixture();
        x.links.registerTrigger(
          TriggerExtension(
            'chat',
            translate: (o) => const FactTrigger(
              'platform.chat',
              Filter({}),
              throttles: [Throttle(Duration(minutes: 2), per: 'user')],
            ),
            accept: (data, o) {
              final m = data as Map;
              return m['text'] == o['chat']
                  ? (data: m, by: Principal('viewer', m['user'] as String))
                  : null;
            },
          ),
        );
        x.use([
          {
            'id': 'clip',
            'when': [
              {'chat': '!clip'},
            ],
            'do': [
              {
                'call': 'test.say',
                'params': {'text': 'clip by {user}'},
              },
            ],
          },
        ]);
        x.chat.emit({'user': 'a', 'text': '!clip'});
        x.chat.emit({'user': 'a', 'text': '!clip'});
        x.chat.emit({'user': 'b', 'text': '!clip'});
        x.chat.emit({'user': 'c', 'text': 'hello'});
        t.flushMicrotasks();
        expect(x.said, ['clip by a', 'clip by b']);
        expect(x.sayers, [
          const Principal('viewer', 'a'),
          const Principal('viewer', 'b'),
        ]);
      });
    });

    test(
      "an extension's throttles are defaults: a link's own replace them",
      () {
        fakeAsync((t) {
          final x = LinksFixture();
          x.links.registerTrigger(
            TriggerExtension(
              'chat',
              translate: (o) => const FactTrigger(
                'platform.chat',
                Filter({}),
                throttles: [Throttle(Duration(minutes: 2))],
              ),
            ),
          );
          x.use([
            {
              'id': 'hi',
              'when': [
                {
                  'chat': '!hi',
                  'throttle': {'every': '1s'},
                },
              ],
              'do': [
                {
                  'call': 'test.say',
                  'params': {'text': 'hi'},
                },
              ],
            },
          ]);
          x.chat.emit({'user': 'a', 'text': '!hi'});
          t.elapse(const Duration(seconds: 2));
          x.chat.emit({'user': 'a', 'text': '!hi'});
          t.flushMicrotasks();
          expect(x.said, ['hi', 'hi']);
        });
      },
    );

    test('a button is a manual trigger the host draws', () async {
      f.use([
        {
          'id': 'brb-button',
          'when': [
            {
              'button': {'label': 'Break', 'icon': 'coffee'},
            },
          ],
          'do': [
            {
              'call': 'studio.show',
              'params': {'scene': 'break'},
            },
          ],
        },
      ]);
      final r = await f.r.call('links.press', {'link': 'brb-button'}, by: user);
      expect((r as CallDone).value, {'ran': true});
      await pumpEventQueue();
      expect(f.r.read('studio.program'), 'break');
    });

    test('an unknown extension leaves the link unresolved', () {
      f.use([
        {
          'id': 'x',
          'when': [
            {'voice': 'hey'},
          ],
          'do': <Object?>[],
        },
      ]);
      expect(f.links.statuses['x']!.missing, ['trigger voice']);
    });
  });
}
