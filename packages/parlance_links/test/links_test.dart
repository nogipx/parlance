import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:parlance/app.dart' show Host;
import 'package:parlance/tools.dart';
import 'package:parlance_links/parlance_links.dart';
import 'package:test/test.dart';

const house = Principal('house');
const plug = Principal('plugin', 'plug');
const user = Principal('user', 'local');

/// A house with a state, a command and a fact, and a plugin whose links
/// run as it.
final class Bench {
  Bench({Callers? callers}) {
    s = host.participant(house, vocabularies: [const WordSet.open('st')]).raw;
    p = host.participant(plug, vocabularies: [const WordSet.open('plug')]).raw;
    level = s.defineState(StateDescriptor('st.level', type: const IntType()));
    said = s.defineFact(
      FactDescriptor(
        'st.said',
        type: const RecordType({
          'visitor': Field(TextType(), optional: true),
          'n': Field(IntType(), optional: true),
        }),
      ),
    );
    s.defineCommand(
      CommandDescriptor(
        'st.note',
        params: const RecordType({
          'n': Field(IntType(), optional: true),
          'visitor': Field(TextType(), optional: true),
        }),
        callers: callers ?? Callers({'plugin': Access.allow}),
      ),
      (call) {
        notes.add((params: call.params, cause: call.cause));
        if (call.params['n'] == -1) throw StateError('no -1');
      },
    );
    links = Links(p, vocabulary: 'plug', onError: (e, _) => errors.add(e));
  }

  final host = Host();
  Registry get registry => host.registry;
  late final IRawParticipant s;
  late final IRawParticipant p;
  late final IStateHandle level;
  late final IFactHandle said;
  late final Links links;
  final notes = <({Map<String, Object?> params, Cause cause})>[];
  final errors = <Object>[];

  Future<void> dispose() async {
    await links.dispose();
    await host.dispose();
  }
}

Future<void> pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a fact said calls as the owner, in the fact\'s conversation', () async {
    final b = Bench();
    addTearDown(b.dispose);
    await b.links.load([
      {
        'id': 'note',
        'when': [
          {
            'fact': 'st.said',
            'where': {
              'n': {'>=': 2},
            },
          },
        ],
        'do': [
          {
            'call': 'st.note',
            'params': {'n': r'$trigger.n', 'visitor': r'$trigger.visitor'},
          },
        ],
      },
    ]);
    b.said.say({'n': 1});
    b.said.say({'n': 3}, id: 'f1');
    await pump();
    expect(b.notes.map((x) => x.params), [
      {'n': 3},
    ]);
    final cause = b.notes.single.cause;
    expect(cause.by, plug);
    expect(cause.parent, 'f1');
    expect(cause.conversationOf('x'), 'f1');
  });

  test('a state the participant may not read: load does not start the '
      'links, and says so', () async {
    final b = Bench();
    addTearDown(b.dispose);
    b.s
        .defineState(
          StateDescriptor(
            'st.secret',
            type: const BoolType(),
            readers: const Callers({'house': Access.allow}),
          ),
        )
        .set(true);
    await b.links.load([
      {
        'id': 'note',
        'only': {'state': 'st.secret', 'is': true},
        'when': [
          {'fact': 'st.said'},
        ],
        'do': [
          {'call': 'st.note'},
        ],
      },
    ]);
    expect(b.errors, isNotEmpty);
    b.said.say({});
    await pump();
    expect(b.notes, isEmpty, reason: 'the links were not started');
  });

  test('a link calls only what its owner may', () async {
    final b = Bench(callers: Callers({'user': Access.allow}));
    addTearDown(b.dispose);
    final runs = <LinkRun>[];
    final links = Links(b.p, vocabulary: 'plug', onRun: runs.add);
    addTearDown(links.dispose);
    await links.load([
      {
        'id': 'note',
        'when': [
          {'fact': 'st.said'},
        ],
        'do': [
          {'call': 'st.note'},
        ],
      },
    ]);
    b.said.say({'n': 1});
    await pump();
    expect(b.notes, isEmpty);
    expect(runs.single.why, isNotNull);
  });

  test('a state becomes: a change fires it, its first value does not, '
      'unless already', () async {
    final b = Bench();
    addTearDown(b.dispose);
    await b.links.load([
      {
        'id': 'changed',
        'when': [
          {'state': 'st.level', 'becomes': 0},
        ],
        'do': [
          {
            'call': 'st.note',
            'params': {'n': 0},
          },
        ],
      },
      {
        'id': 'already',
        'when': [
          {'state': 'st.level', 'becomes': 0, 'already': true},
        ],
        'do': [
          {
            'call': 'st.note',
            'params': {'n': 100},
          },
        ],
      },
    ]);
    b.level.set(0);
    await pump();
    expect(b.notes.map((x) => x.params['n']), [100]);
    b.level.set(5);
    await pump();
    b.level.set(0);
    await pump();
    expect(b.notes.map((x) => x.params['n']), [100, 0, 100]);
  });

  test('already fires for what holds when the link starts', () async {
    final b = Bench();
    addTearDown(b.dispose);
    b.level.set(0);
    await b.links.load([
      {
        'id': 'already',
        'when': [
          {'state': 'st.level', 'becomes': 0, 'already': true},
        ],
        'do': [
          {'call': 'st.note'},
        ],
      },
    ]);
    await pump();
    expect(b.notes, hasLength(1));
  });

  test('for: fires once the value held that long, not when it went', () {
    fakeAsync((async) {
      final b = Bench();
      unawaited(
        b.links.load([
          {
            'id': 'quiet',
            'when': [
              {'state': 'st.level', 'becomes': 0, 'for': '1m'},
            ],
            'do': [
              {'call': 'st.note'},
            ],
          },
        ]),
      );
      b.level.set(1);
      async.flushMicrotasks();
      b.level.set(0);
      async.elapse(const Duration(seconds: 30));
      b.level.set(2);
      async.elapse(const Duration(minutes: 2));
      expect(b.notes, isEmpty);
      b.level.set(0);
      async.elapse(const Duration(seconds: 61));
      expect(b.notes, hasLength(1));
      unawaited(b.dispose());
      async.flushMicrotasks();
    });
  });

  test('only holds a run back while it does not hold', () async {
    final b = Bench();
    addTearDown(b.dispose);
    b.level.set(0);
    await b.links.load([
      {
        'id': 'note',
        'when': [
          {'fact': 'st.said'},
        ],
        'only': {'state': 'st.level', '>': 0},
        'do': [
          {'call': 'st.note'},
        ],
      },
    ]);
    b.said.say({});
    await pump();
    b.level.set(1);
    await pump();
    b.said.say({});
    await pump();
    expect(b.notes, hasLength(1));
  });

  test('a throttle per visitor lets each through once in its while', () {
    fakeAsync((async) {
      final b = Bench();
      unawaited(
        b.links.load([
          {
            'id': 'note',
            'when': [
              {
                'fact': 'st.said',
                'throttle': {'every': '1m', 'per': r'$trigger.visitor'},
              },
            ],
            'do': [
              {
                'call': 'st.note',
                'params': {'visitor': r'$trigger.visitor'},
              },
            ],
          },
        ]),
      );
      async.flushMicrotasks();
      for (final v in ['ann', 'ann', 'bob']) {
        b.said.say({'visitor': v});
        async.flushMicrotasks();
      }
      async.elapse(const Duration(minutes: 1));
      b.said.say({'visitor': 'ann'});
      async.flushMicrotasks();
      expect(b.notes.map((x) => x.params['visitor']), ['ann', 'bob', 'ann']);
      unawaited(b.dispose());
      async.flushMicrotasks();
    });
  });

  test('a throttle per visitor holds back each it let through, however many '
      'visitors came', () {
    fakeAsync((async) {
      final b = Bench();
      unawaited(
        b.links.load([
          {
            'id': 'note',
            'when': [
              {
                'fact': 'st.said',
                'throttle': {'every': '1m', 'per': r'$trigger.visitor'},
              },
            ],
            'do': [
              {
                'call': 'st.note',
                'params': {'visitor': r'$trigger.visitor'},
              },
            ],
          },
        ]),
      );
      async.flushMicrotasks();
      for (var i = 0; i < 300; i++) {
        b.said.say({'visitor': 'v$i'});
        async.flushMicrotasks();
      }
      b.said.say({'visitor': 'v0'});
      async.flushMicrotasks();
      expect(b.notes, hasLength(300), reason: 'v0 is held back still');
      async.elapse(const Duration(minutes: 2));
      b.said.say({'visitor': 'v1'});
      async.flushMicrotasks();
      expect(b.notes, hasLength(301));
      unawaited(b.dispose());
      async.flushMicrotasks();
    });
  });

  test('a button is shown under the owner, lit and pressed as it', () async {
    final b = Bench();
    addTearDown(b.dispose);
    b.level.set(0);
    await b.links.load([
      {
        'id': 'up',
        'when': [
          {
            'button': {
              'label': 'Up',
              'litLabel': 'Up!',
              'icon': 'up',
              'lit': {'state': 'st.level', 'is': 1},
            },
          },
        ],
        'do': [
          {
            'call': 'st.note',
            'params': {'n': 1},
          },
        ],
      },
    ]);
    await pump();
    final desk = b.host.participant(user).raw;
    expect(desk.read('plug.links.buttons'), [
      {'id': 'up', 'icon': 'up', 'label': 'Up', 'lit': false},
    ]);
    b.level.set(1);
    await pump();
    expect((desk.read('plug.links.buttons')! as List).single, {
      'id': 'up',
      'icon': 'up',
      'label': 'Up!',
      'lit': true,
    });
    final r = await desk.call('plug.links.press', {'button': 'up'});
    expect(r, isA<CallDone<Object?>>());
    expect(b.notes.single.cause.by, plug);
  });

  test('a button whose command cannot run says why', () async {
    final b = Bench(callers: Callers({'user': Access.allow}));
    addTearDown(b.dispose);
    await b.links.load([
      {
        'id': 'up',
        'when': [
          {
            'button': {'label': 'Up'},
          },
        ],
        'do': [
          {'call': 'st.note'},
        ],
      },
    ]);
    await pump();
    final shown = (b.p.read('plug.links.buttons')! as List).single as Map;
    expect(shown['unavailable'], isNotNull);
    expect(await b.links.press('up'), isNotNull);
  });

  test(
    'an extension stands for a trigger, and picks what a run gets',
    () async {
      final b = Bench();
      addTearDown(b.dispose);
      final links = Links(
        b.p,
        vocabulary: 'plug',
        extensions: [
          TriggerExtension(
            'says',
            translate: (o) => const FactTrigger('st.said', Filter({})),
            accept: (data, o) => (data! as Map)['visitor'] == o['says']
                ? {'visitor': 'it was ${o['says']}'}
                : null,
          ),
        ],
      );
      addTearDown(links.dispose);
      await links.load([
        {
          'id': 'note',
          'when': [
            {'says': 'ann'},
          ],
          'do': [
            {
              'call': 'st.note',
              'params': {'visitor': r'$trigger.visitor'},
            },
          ],
        },
      ]);
      b.said.say({'visitor': 'bob'});
      b.said.say({'visitor': 'ann'});
      await pump();
      expect(b.notes.single.params, {'visitor': 'it was ann'});
    },
  );

  test(
    'links that set each other off stop at the conversation\'s limit',
    () async {
      final b = Bench();
      addTearDown(b.dispose);
      // A command that says the fact that calls it.
      b.s.defineCommand(
        CommandDescriptor(
          'st.again',
          callers: Callers({'plugin': Access.allow}),
        ),
        (call) => b.said.say({}, cause: call.causeFor(house)),
      );
      var runs = 0;
      final links = Links(
        b.p,
        vocabulary: 'plug',
        conversationLimit: 5,
        onRun: (_) => runs++,
        onError: (e, _) => b.errors.add(e),
      );
      addTearDown(links.dispose);
      await links.load([
        {
          'id': 'loop',
          'mode': 'queue',
          'when': [
            {'fact': 'st.said'},
          ],
          'do': [
            {'call': 'st.again'},
          ],
        },
      ]);
      b.said.say({});
      for (var i = 0; i < 20; i++) {
        await pump();
      }
      expect(runs, 5);
      expect(b.errors, isNotEmpty);
    },
  );

  test('a link that stops ends its runs: one waiting in a step, and those '
      'waiting their turn', () async {
    final b = Bench();
    addTearDown(b.dispose);
    await b.links.load([
      {
        'id': 'slow',
        'mode': 'queue',
        'when': [
          {
            'button': {'label': 'Slow'},
          },
        ],
        'do': [
          {'wait': '1h'},
        ],
      },
    ]);
    await pump();
    final first = b.links.press('slow');
    final second = b.links.press('slow');
    await pump();
    await b.links.dispose();
    expect(
      await Future.wait([first, second]).timeout(const Duration(seconds: 1)),
      ['stopped', 'stopped'],
    );
  });

  test("a host's onRun that throws is told; the runs waiting go on", () async {
    final b = Bench();
    addTearDown(b.dispose);
    final errors = <Object>[];
    final links = Links(
      b.p,
      vocabulary: 'plug',
      onRun: (_) => throw StateError('onRun'),
      onError: (e, _) => errors.add(e),
    );
    addTearDown(links.dispose);
    await links.load([
      {
        'id': 'note',
        'mode': 'queue',
        'when': [
          {'fact': 'st.said'},
        ],
        'do': [
          {
            'call': 'st.note',
            'params': {'n': r'$trigger.n'},
          },
        ],
      },
    ]);
    b.said.say({'n': 1});
    b.said.say({'n': 2});
    await pump();
    expect([for (final n in b.notes) n.params['n']], [1, 2]);
    expect(errors, hasLength(2));
  });

  test(
    'a load made while another reads its states is the one that runs',
    () async {
      final b = Bench();
      addTearDown(b.dispose);
      Map<String, Object?> link(String id) => {
        'id': id,
        'only': {'state': 'st.level', '>': 0},
        'when': [
          {'fact': 'st.said'},
          {
            'button': {'label': id},
          },
        ],
        'do': [
          {
            'call': 'st.note',
            'params': {'visitor': id},
          },
        ],
      };
      b.level.set(1);
      final first = b.links.load([link('one')]);
      final second = b.links.load([link('two')]);
      await Future.wait([first, second]);
      b.said.say({});
      await pump();
      expect([for (final n in b.notes) n.params['visitor']], ['two']);
      expect(b.errors, isEmpty);
      expect([for (final x in b.links.buttons()) x['id']], ['two']);
    },
  );

  test('a link that cannot be taken is told; the others run', () async {
    final b = Bench();
    addTearDown(b.dispose);
    await b.links.load([
      {'id': 'bad', 'when': <Object?>[], 'do': <Object?>[]},
      {
        'id': 'odd',
        'when': [
          {'nothing': 1},
        ],
      },
      {
        'id': 'many',
        'queueLimit': '10',
        'when': [
          {'fact': 'st.said'},
        ],
      },
      {
        'id': 'keyed',
        'when': [
          {'state': 'st.level', 'key': 5, 'becomes': 1},
        ],
      },
      {
        'id': 'good',
        'when': [
          {'fact': 'st.said'},
        ],
        'do': [
          {'call': 'st.note'},
        ],
      },
    ]);
    expect(b.links.problems.map((x) => x.link), [
      'bad',
      'odd',
      'many',
      'keyed',
    ]);
    b.said.say({});
    await pump();
    expect(b.notes, hasLength(1));
  });

  test('a run that stops short says at which step', () async {
    final b = Bench();
    addTearDown(b.dispose);
    await b.links.load([
      {
        'id': 'two',
        'when': [
          {
            'button': {'label': 'Two'},
          },
        ],
        'do': [
          {
            'call': 'st.note',
            'params': {'n': 1},
          },
          {
            'call': 'st.note',
            'params': {'n': -1},
          },
        ],
      },
    ]);
    final why = await b.links.press('two');
    expect(why, startsWith('step 2 of 2 (st.note), after step 1 done: '));
  });
  group('when the world fails', () {
    test('a link that stops ends a run waiting on a call that does not '
        'answer', () async {
      final b = Bench();
      addTearDown(b.dispose);
      final never = Completer<void>();
      b.s.defineCommand(
        CommandDescriptor(
          'st.hang',
          callers: Callers({'plugin': Access.allow}),
          deadline: const Duration(hours: 1),
        ),
        (_) => never.future,
      );
      await b.links.load([
        {
          'id': 'hang',
          'when': [
            {
              'button': {'label': 'Hang'},
            },
          ],
          'do': [
            {'call': 'st.hang'},
            {'call': 'st.note'},
          ],
        },
      ]);
      final pressed = b.links.press('hang');
      await pump();
      await b.links.dispose();
      expect(await pressed.timeout(const Duration(seconds: 1)), 'stopped');
      never.complete();
      await pump();
      expect(b.notes, isEmpty, reason: 'no step after it');
    });

    test(
      "an extension's accept that throws is told; the other links run",
      () async {
        final b = Bench();
        addTearDown(b.dispose);
        final errors = <Object>[];
        final links = Links(
          b.p,
          vocabulary: 'plug',
          onError: (e, _) => errors.add(e),
          extensions: [
            TriggerExtension(
              'says',
              translate: (o) => const FactTrigger('st.said', Filter({})),
              accept: (data, o) => throw StateError('accept'),
            ),
          ],
        );
        addTearDown(links.dispose);
        await links.load([
          {
            'id': 'odd',
            'when': [
              {'says': 'ann'},
            ],
            'do': [
              {'call': 'st.note'},
            ],
          },
          {
            'id': 'plain',
            'when': [
              {'fact': 'st.said'},
            ],
            'do': [
              {'call': 'st.note'},
            ],
          },
        ]);
        b.said.say({});
        await pump();
        expect(b.notes, hasLength(1));
        expect(errors, [isA<StateError>()]);
      },
    );

    test(
      "an extension's translate that throws makes its link a problem",
      () async {
        final b = Bench();
        addTearDown(b.dispose);
        final links = Links(
          b.p,
          vocabulary: 'plug',
          extensions: [
            TriggerExtension(
              'says',
              translate: (o) => throw StateError('translate'),
            ),
          ],
        );
        addTearDown(links.dispose);
        await links.load([
          {
            'id': 'odd',
            'when': [
              {'says': 'ann'},
            ],
          },
          {
            'id': 'plain',
            'when': [
              {'fact': 'st.said'},
            ],
            'do': [
              {'call': 'st.note'},
            ],
          },
        ]);
        expect([for (final x in links.problems) x.link], ['odd']);
        b.said.say({});
        await pump();
        expect(b.notes, hasLength(1));
      },
    );
  });
}
