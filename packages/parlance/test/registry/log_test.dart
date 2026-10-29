import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:parlance/tools.dart';
import 'package:rpc_dart/logger.dart';
import 'package:test/test.dart';

import 'fixture.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

void main() {
  late LogController logs;
  late List<LogRecord> records;

  setUp(() {
    logs = LogController();
    records = [];
    logs.stream.listen(records.add);
  });
  tearDown(() => logs.dispose());

  Iterable<LogSpan> spans() => records.whereType<LogSpan>();
  Iterable<LogEvent> events() => records.whereType<LogEvent>();

  test('a call is a span; a call its handler makes is its child, in its '
      'trace; what it wrote is an event of it', () async {
    final f = Fixture(
      registry: Registry(log: logs.scope('parlance'), onError: (e, _) {}),
    );
    f.r.defineCommand(
      CommandDescriptor('house.open', callers: Callers.only(['user'])),
      (c) async {
        c.span.event('opening');
        await f.r.call(
          'house.show',
          {'room': 'break'},
          by: user,
          cause: c.causeFor(user),
        );
      },
    );
    await f.r.call('house.open', {}, by: user, id: 'outer');
    await pumpEventQueue();

    final open = spans().singleWhere((s) => s.name == 'house.open');
    final show = spans().singleWhere((s) => s.name == 'house.show');
    expect(open.scope, 'parlance.calls');
    expect(open.traceId, matches(RegExp(r'^[0-9a-f]{32}$')), reason: 'W3C');
    expect(open.data, containsPair('call', 'outer'));
    expect(open.data, containsPair('by', user.selector));
    expect(open.events.map((e) => e.message), contains('opening'));
    expect(show.parentSpanId, open.spanId);
    expect(show.traceId, open.traceId);
    expect(show.data, containsPair('parent', 'outer'));
    expect(show.status, LogSpanStatus.ok);
    final wrote = show.events.singleWhere((e) => e.message == 'wrote');
    expect(wrote.data, containsPair('state', 'house.focus'));
    await f.r.dispose();
  });

  test('a call that answers a fact said in another call links that call\'s '
      'span', () async {
    final r = Registry(log: logs.scope('parlance'), onError: (e, _) {});
    final said = r.defineFact(
      FactDescriptor('x.said', type: const TextType()),
      by: owner,
    );
    r.defineCommand(
      CommandDescriptor('x.say', callers: Callers.only(['user'])),
      (c) => said.emit('hi', cause: c.causeFor(owner)),
    );
    r.defineCommand(
      CommandDescriptor('x.answer', callers: Callers.only(['user'])),
      (_) {},
    );
    r
        .facts(fact: 'x.said')
        .listen(
          (f) => r.call(
            'x.answer',
            {},
            by: user,
            cause: Cause(user, parent: f.id),
          ),
        );
    await r.call('x.say', {}, by: user);
    await pumpEventQueue();
    final say = spans().singleWhere((s) => s.name == 'x.say');
    final answer = records.whereType<LogSpanStart>().singleWhere(
      (s) => s.name == 'x.answer',
    );
    expect(answer.links, ['00-${say.traceId}-${say.spanId}-01']);
    expect(answer.traceId, isNot(say.traceId), reason: 'a trace of its own');
    await r.dispose();
  });

  test(
    'questions asked meanwhile do not push out the trace a fact keeps',
    () async {
      final r = Registry(
        log: logs.scope('parlance'),
        retainTicks: 2,
        onError: (e, _) {},
      );
      final said = r.defineFact(
        FactDescriptor('x.said', type: const TextType()),
        by: owner,
      );
      r.defineCommand(
        CommandDescriptor('x.say', callers: Callers.only(['user'])),
        (c) => said.emit('hi', cause: c.causeFor(owner)),
      );
      r.defineQuery(
        QueryDescriptor(
          'x.ask',
          returns: const IntType(),
          askers: Callers.only(['user']),
        ),
        (_) => 1,
      );
      r.defineCommand(
        CommandDescriptor('x.answer', callers: Callers.only(['user'])),
        (_) {},
      );
      String? fact;
      r.facts(fact: 'x.said').listen((f) => fact = f.id);
      await r.call('x.say', {}, by: user);
      await pumpEventQueue();
      for (var i = 0; i < 5; i++) {
        await r.call('x.ask', {}, by: user);
      }
      await r.call(
        'x.answer',
        {},
        by: user,
        cause: Cause(user, parent: fact),
      );
      await pumpEventQueue();
      final answer = records.whereType<LogSpanStart>().singleWhere(
        (s) => s.name == 'x.answer',
      );
      expect(answer.links, hasLength(1));
      await r.dispose();
    },
  );

  test('a refusal is told, and opens no span; a failure ends its span as an '
      'error, with where it was thrown', () async {
    final r = Registry(log: logs.scope('parlance'), onError: (e, _) {});
    r.defineCommand(
      CommandDescriptor('x.bad', callers: Callers.only(['user'])),
      (_) => throw StateError('no'),
    );
    await r.call('x.bad', {}, by: visitor);
    await r.call('x.bad', {}, by: user);
    await pumpEventQueue();
    final refused = events().singleWhere((e) => e.message == 'refused');
    expect(refused.level, RpcLogLevel.info);
    expect(refused.data, containsPair('command', 'x.bad'));
    expect(refused.data, containsPair('code', 'notPermitted'));
    expect(refused.data, containsPair('by', visitor.selector));
    expect(spans().single.status, LogSpanStatus.error);
    expect('${spans().single.stackTrace}', contains('log_test.dart'));
    await r.dispose();
  });

  test('a call that timed out stays open until its handler ends, late', () {
    fakeAsync((t) {
      final r = Registry(log: logs.scope('parlance'));
      final slow = Completer<void>();
      r.defineCommand(
        CommandDescriptor(
          'x.slow',
          callers: Callers.only(['user']),
          deadline: const Duration(seconds: 1),
        ),
        (_) => slow.future,
      );
      r.call('x.slow', {}, by: user);
      t.elapse(const Duration(seconds: 2));
      expect(spans(), isEmpty);
      slow.complete();
      t.flushMicrotasks();
      final span = spans().single;
      expect(span.events.map((e) => e.message), ['timed out']);
      expect(span.data, containsPair('late', true));
    });
  });

  test('the catalog and the ticks are told, and errors', () async {
    final r = Registry(log: logs.scope('parlance'), onError: (e, _) {});
    final on = r.defineState(
      StateDescriptor('x.on', type: const BoolType()),
      by: owner,
    );
    on.set(true);
    r.addGuard('bad', (_) => throw StateError('boom'));
    r.defineCommand(
      CommandDescriptor('x.go', callers: Callers.only(['user'])),
      (_) {},
    );
    await r.call('x.go', {}, by: user);
    await pumpEventQueue();
    expect(
      [
        for (final e in events())
          if (e.scope == 'parlance.catalog') (e.message, e.data?['word']),
      ],
      [('defined', 'x.on'), ('defined', 'x.go')],
    );
    final tick = events().singleWhere((e) => e.scope == 'parlance.ticks');
    expect(tick.data, containsPair('changes', ['x.on']));
    expect(
      events().singleWhere((e) => e.level == RpcLogLevel.error).error,
      isA<StateError>(),
    );
    await r.dispose();
  });

  test('spans are telemetry: kept whatever the level; what the level does '
      'not take is not made', () async {
    final quiet = LogController(minLevel: RpcLogLevel.warning);
    final kept = <LogRecord>[];
    quiet.stream.listen(kept.add);
    final f = Fixture(
      registry: Registry(log: quiet.scope('parlance'), onError: (e, _) {}),
    );
    await f.r.call('house.show', {'room': 'break'}, by: user);
    await f.r.call('house.show', {'room': 'break'}, by: owner);
    await pumpEventQueue();
    final span = kept.whereType<LogSpan>().single;
    expect(span.name, 'house.show');
    expect(span.events, isEmpty, reason: 'its writes are told at debug');
    expect(span.data, isNot(contains('params')));
    expect(kept.whereType<LogEvent>(), isEmpty);
    await f.r.dispose();
    quiet.dispose();
  });

  test('with spans off a call keeps no span; what its handler logs is told '
      'as plain events', () async {
    final off = LogController(spansEnabled: false);
    final kept = <LogRecord>[];
    off.stream.listen(kept.add);
    final r = Registry(log: off.scope('p'), onError: (e, _) {});
    r.defineCommand(
      CommandDescriptor('x.go', callers: Callers.only(['user'])),
      (c) => c.span.event('step'),
    );
    expect((await r.call('x.go', {}, by: user)).ok, isTrue);
    await pumpEventQueue();
    expect(kept.whereType<LogSpanStart>(), isEmpty);
    expect(kept.whereType<LogSpan>(), isEmpty);
    expect(kept.whereType<LogEvent>().map((e) => e.message), contains('step'));
    await r.dispose();
    off.dispose();
  });

  test('without a log, a call\'s span is the one of LogScope.noop: ended, '
      'nothing kept', () async {
    final r = Registry();
    final seen = <LogSpanHandle>[];
    r.defineCommand(
      CommandDescriptor('x.go', callers: Callers.only(['user'])),
      (c) => seen.add(c.span),
    );
    expect((await r.call('x.go', {}, by: user)).ok, isTrue);
    expect((await r.call('x.go', {}, by: user)).ok, isTrue);
    expect(r.log, same(LogScope.noop));
    expect(seen.first, same(seen.last), reason: 'one span, made once');
    expect(seen.first.isEnded, isTrue);
    expect(seen.first.isEnabled(RpcLogLevel.fatal), isFalse);
    expect(seen.first.traceparent, isNull);
    await r.dispose();
  });
}
