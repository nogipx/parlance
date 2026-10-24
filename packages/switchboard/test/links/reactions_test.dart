import 'package:fake_async/fake_async.dart';
import 'package:switchboard/links.dart';
import 'package:switchboard/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  late LinksFixture f;
  setUp(() => f = LinksFixture());

  test(
    'a fact with a filter runs the steps, with references and templates',
    () async {
      f.use([
        {
          'id': 'raid',
          'when': [
            {
              'fact': 'platform.raid',
              'where': {
                'viewers': {'>=': 10},
              },
            },
          ],
          'do': [
            {
              'call': 'test.say',
              'params': {'text': '{from} raided with {viewers}'},
            },
            {
              'call': 'test.say',
              'params': {r'text': r'$trigger.viewers'},
            },
            {
              'call': 'studio.show',
              'params': {'scene': 'break'},
            },
          ],
        },
      ]);
      f.raid.emit({'from': 'small', 'viewers': 3});
      f.raid.emit({'from': 'big', 'viewers': 12});
      await pumpEventQueue();
      expect(f.said, ['big raided with 12', 12]);
      expect(f.sayers.first, const Principal.link('raid'));
      expect(f.r.read('studio.program'), 'break');
    },
  );

  test('a state trigger: becomes, leaves, changes from and to', () async {
    f.use([
      {
        'id': 'in',
        'when': [
          {'state': 'studio.program', 'becomes': 'break'},
        ],
        'do': [
          {
            'call': 'test.say',
            'params': {'text': 'in'},
          },
        ],
      },
      {
        'id': 'out',
        'when': [
          {'state': 'studio.program', 'leaves': 'break'},
        ],
        'do': [
          {
            'call': 'test.say',
            'params': {'text': r'out to {value}'},
          },
        ],
      },
      {
        'id': 'main-from-test',
        'when': [
          {
            'state': 'studio.program',
            'changes': {'from': 'test', 'to': 'main'},
          },
        ],
        'do': [
          {
            'call': 'test.say',
            'params': {'text': 'test->main'},
          },
        ],
      },
    ]);
    for (final s in ['main', 'break', 'test', 'main']) {
      f.program.set(s);
      await pumpEventQueue();
    }
    expect(f.said, ['in', 'out to test', 'test->main']);
  });

  test('for: fires only when the state stays', () {
    fakeAsync((t) {
      final x = LinksFixture();
      x.use([
        {
          'id': 'quiet',
          'when': [
            {'state': 'audio.muted', 'becomes': true, 'for': '20m'},
          ],
          'do': [
            {
              'call': 'test.say',
              'params': {'text': 'still muted'},
            },
          ],
        },
      ]);
      x.muted.set(true);
      t.elapse(const Duration(minutes: 10));
      x.muted.set(false);
      t.elapse(const Duration(minutes: 15));
      expect(x.said, isEmpty);
      x.muted.set(true);
      t.elapse(const Duration(minutes: 21));
      expect(x.said, ['still muted']);
    });
  });

  test('every and at', () {
    fakeAsync((t) {
      final x = LinksFixture();
      x.use([
        {
          'id': 'tick',
          'when': [
            {'every': '15m'},
          ],
          'do': [
            {
              'call': 'test.say',
              'params': {'text': 'tick'},
            },
          ],
        },
        {
          'id': 'evening',
          'when': [
            {'at': '20:00'},
          ],
          'do': [
            {
              'call': 'test.say',
              'params': {'text': 'evening'},
            },
          ],
        },
      ]);
      t.elapse(const Duration(minutes: 46));
      expect(x.said.where((s) => s == 'tick'), hasLength(3));
      t.elapse(const Duration(hours: 25));
      expect(x.said.where((s) => s == 'evening'), hasLength(1));
    });
  });

  test('throttle per key, once until reset', () {
    fakeAsync((t) {
      final x = LinksFixture();
      x.use([
        {
          'id': 'greet',
          'when': [
            {
              'fact': 'platform.raid',
              'throttle': {'every': '1m', 'per': r'$trigger.from'},
            },
          ],
          'do': [
            {
              'call': 'test.say',
              'params': {'text': '{from}'},
            },
          ],
        },
        {
          'id': 'first',
          'when': [
            {'fact': 'platform.raid', 'once': true},
          ],
          'do': [
            {
              'call': 'test.say',
              'params': {'text': 'first!'},
            },
          ],
        },
      ]);
      x.raid.emit({'from': 'a', 'viewers': 1});
      x.raid.emit({'from': 'a', 'viewers': 1});
      x.raid.emit({'from': 'b', 'viewers': 1});
      t.elapse(const Duration(seconds: 61));
      x.raid.emit({'from': 'a', 'viewers': 1});
      t.flushMicrotasks();
      expect(x.said, ['a', 'first!', 'b', 'a']);
      x.r.call('links.reset', {'link': 'first'}, by: user);
      t.flushMicrotasks();
      x.raid.emit({'from': 'c', 'viewers': 1});
      t.flushMicrotasks();
      expect(x.said.last, 'first!');
    });
  });

  test('only: conditions on state', () async {
    f.use([
      {
        'id': 'muted-raid',
        'when': [
          {'fact': 'platform.raid'},
        ],
        'only': [
          {'state': 'audio.muted', 'is': true},
        ],
        'do': [
          {
            'call': 'test.say',
            'params': {'text': 'unmute!'},
          },
        ],
      },
    ]);
    f.raid.emit({'from': 'a', 'viewers': 1});
    f.muted.set(true);
    f.raid.emit({'from': 'b', 'viewers': 1});
    await pumpEventQueue();
    expect(f.said, ['unmute!']);
  });

  test(
    'modes: single skips, restart cancels and drops its layers, queue waits',
    () {
      fakeAsync((t) {
        Map<String, Object?> slow(String id, String mode) => {
          'id': id,
          'mode': mode,
          'when': [
            {'manual': <String, Object?>{}},
          ],
          'do': [
            {
              'call': 'test.say',
              'params': {'text': '$id:start'},
            },
            {
              'temporarily': {
                'for': '10s',
                'do': [
                  {
                    'call': 'audio.mute',
                    'params': {'on': true},
                  },
                ],
              },
            },
            {'wait': '5s'},
            {
              'call': 'test.say',
              'params': {'text': '$id:end'},
            },
          ],
        };
        final x = LinksFixture();
        x.muted.set(false);
        x.use([slow('s', 'single'), slow('r', 'restart'), slow('q', 'queue')]);
        void press(String id) =>
            x.r.call('links.press', {'link': id}, by: user);

        press('s');
        t.elapse(const Duration(seconds: 1));
        press('s');
        t.elapse(const Duration(seconds: 20));
        expect(x.said, ['s:start', 's:end']);
        expect(x.r.read('audio.muted'), false);

        x.said.clear();
        press('r');
        t.elapse(const Duration(seconds: 1));
        press('r');
        t.elapse(const Duration(seconds: 6));
        expect(x.said, ['r:start', 'r:start', 'r:end']);
        t.elapse(const Duration(seconds: 10));
        expect(x.r.read('audio.muted'), false);

        x.said.clear();
        press('q');
        t.elapse(const Duration(seconds: 1));
        press('q');
        t.elapse(const Duration(seconds: 8));
        expect(x.said, [
          'q:start',
          'q:end',
        ], reason: 'the second waits for the temporary');
        t.elapse(const Duration(seconds: 30));
        expect(x.said, ['q:start', 'q:end', 'q:start', 'q:end']);
      });
    },
  );

  test('a refusal stops the run unless orContinue', () async {
    f.use([
      {
        'id': 'r',
        'when': [
          {'manual': <String, Object?>{}},
        ],
        'do': [
          {
            'call': 'studio.show',
            'params': {'scene': 'nowhere'},
            'orContinue': true,
          },
          {
            'call': 'studio.show',
            'params': {'scene': 'nowhere'},
          },
          {
            'call': 'test.say',
            'params': {'text': 'never'},
          },
        ],
      },
    ]);
    await f.r.call('links.press', {'link': 'r'}, by: user);
    await pumpEventQueue();
    expect(f.said, isEmpty);
    expect(f.links.statuses['r']!.reason, contains('invalidParams'));
  });

  test('flip, waitUntil a fact, waitUntil a condition, a timeout', () {
    fakeAsync((t) {
      final x = LinksFixture();
      x.muted.set(false);
      x.use([
        {
          'id': 'w',
          'when': [
            {'manual': <String, Object?>{}},
          ],
          'do': [
            {'flip': 'audio.muted'},
            {
              'waitUntil': {'fact': 'platform.raid'},
              'timeout': '1m',
            },
            {
              'call': 'test.say',
              'params': {'text': 'raided'},
            },
            {
              'waitUntil': {'state': 'studio.program', 'is': 'main'},
              'timeout': '1m',
            },
            {
              'call': 'test.say',
              'params': {'text': 'on main'},
            },
            {
              'waitUntil': {'fact': 'platform.raid'},
              'timeout': '5s',
            },
            {
              'call': 'test.say',
              'params': {'text': 'never'},
            },
          ],
        },
      ]);
      x.r.call('links.press', {'link': 'w'}, by: user);
      t.flushMicrotasks();
      expect(x.r.read('audio.muted'), true);
      x.raid.emit({'from': 'a', 'viewers': 1});
      t.flushMicrotasks();
      x.program.set('main');
      t.elapse(const Duration(seconds: 10));
      expect(x.said, ['raided', 'on main']);
    });
  });

  test('temporarily until a state', () async {
    f.muted.set(false);
    f.use([
      {
        'id': 't',
        'when': [
          {'manual': <String, Object?>{}},
        ],
        'do': [
          {
            'temporarily': {
              'until': {'state': 'studio.program', 'is': 'main'},
              'do': [
                {
                  'call': 'audio.mute',
                  'params': {'on': true},
                },
              ],
            },
          },
        ],
      },
    ]);
    await f.r.call('links.press', {'link': 't'}, by: user);
    await pumpEventQueue();
    expect(f.r.read('audio.muted'), true);
    f.program.set('main');
    await pumpEventQueue();
    expect(f.r.read('audio.muted'), false);
  });

  test('a loop stops at the chain; too many runs disable the link', () async {
    final x = LinksFixture(rateLimit: 3);
    x.use([
      {
        'id': 'echo',
        'when': [
          {'state': 'audio.muted', 'changes': <String, Object?>{}},
        ],
        'do': [
          {'flip': 'audio.muted'},
        ],
      },
      {
        'id': 'spam',
        'when': [
          {'fact': 'platform.raid'},
        ],
        'do': [
          {
            'call': 'test.say',
            'params': {'text': 'x'},
          },
        ],
      },
    ]);
    x.muted.set(true);
    await pumpEventQueue();
    expect(x.r.read('audio.muted'), false, reason: 'flipped once, not again');
    final disabled = <FactMessage>[];
    x.r.facts(fact: 'links.disabled').listen(disabled.add);
    for (var i = 0; i < 5; i++) {
      x.raid.emit({'from': 'a', 'viewers': 1});
    }
    await pumpEventQueue();
    expect(x.said, hasLength(3));
    expect(x.stateOf('spam'), LinkState.disabled);
    expect((disabled.single.payload as Map)['link'], 'spam');
    await x.r.call('links.enabled.set', {'link': 'spam', 'on': true}, by: user);
    expect(x.stateOf('spam'), LinkState.active);
  });

  test('try runs a reaction with test set', () async {
    final changes = <StateChange>[];
    f.r.ticks.listen((t) => changes.addAll(t.changes));
    f.use([
      {
        'id': 'r',
        'when': [
          {'fact': 'platform.raid'},
        ],
        'do': [
          {
            'call': 'audio.mute',
            'params': {'on': true},
          },
        ],
      },
    ]);
    final r = await f.r.call('links.try', {'link': 'r'}, by: user);
    await pumpEventQueue();
    expect((r as CallDone).value, {'ran': true});
    expect(
      changes.firstWhere((c) => c.state == 'audio.muted').cause.test,
      isTrue,
    );
  });
}
