import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:test/test.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const owner = Principal('host', 'house');
const user = Principal('user', 'local');

Future<void> pump() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a watcher that comes late is not told what came before it', () async {
    final r = Registry();
    final w = r.defineState(
      StateDescriptor('a.x', type: const IntType()),
      by: owner,
    );
    r.watch('a.x').listen((_) {});
    await pump();
    w.set(1);
    w.set(2);
    final late = <Object?>[];
    r.watch('a.x').listen(late.add);
    await pump();
    expect(late, [2]);
  });

  test('a state that goes inside a batch tells its watchers so', () async {
    final r = Registry();
    final w = r.defineState(
      StateDescriptor('a.chime', type: const IntType(), key: 'input'),
      by: owner,
    );
    final ticks = <Tick>[];
    r.ticks.listen(ticks.add);
    final seen = <Object?>[];
    r.watch('a.chime', key: 'front').listen(seen.add);
    await pump();
    w.set(5, key: 'front');
    await pump();

    r.batch(() {
      w.set(6, key: 'front');
      w.set(7, key: 'line');
      w.dispose();
    });
    await pump();

    expect(seen, [null, 5, null]);
    expect(r.stateDescriptor('a.chime'), isNull);
    expect(ticks.last.changes.map((c) => (c.key, c.removed)), [
      ('front', true),
    ]);
    // The name is free, and the word comes back with nothing of the old.
    r.defineState(
      StateDescriptor('a.chime', type: const IntType(), key: 'input'),
      by: owner,
    );
    expect(r.readAll('a.chime'), isEmpty);
  });

  test('the late end of a call takes the place of its timeout in what is '
      'kept', () async {
    final r = Registry(retainBytes: 2000);
    r.defineCommand(
      CommandDescriptor(
        'a.slow',
        callers: Callers.only(['user']),
        deadline: const Duration(milliseconds: 1),
      ),
      (_) => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await Future.wait([
      for (var i = 0; i < 50; i++) r.call('a.slow', {}, by: user, id: 't$i'),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (var i = 0; i < 50; i++) {
      expect(r.callRecord('t$i')?.late, isTrue, reason: 't$i');
    }
  });

  test('no recent facts are asked for by a count of none or less', () {
    final r = Registry();
    r.defineFact(FactDescriptor('a.f', type: const IntType()), by: owner)
      ..say(1)
      ..say(2);
    expect(r.recent('a.f', 0), isEmpty);
    expect(r.recent('a.f', -3), isEmpty);
  });

  test('null is a value of its own for a nullable field with a default', () {
    final r = Registry();
    const t = RecordType({
      'x': Field(NullableType(IntType()), defaultValue: 5),
      'y': Field(IntType(), defaultValue: 1),
    });
    expect(t.check({'x': null, 'y': null}, r), {'x': null, 'y': 1});
    expect(t.check(<String, Object?>{}, r), {'x': 5, 'y': 1});
  });

  test('an end this side does not know is not taken for one it does', () {
    expect(
      CallResult.fromJson({'refused': 'somethingNew', 'reason': 'r'}),
      isA<CallFailed>(),
    );
    expect(CallResult.fromJson({'whatever': 1}), isA<CallFailed>());
    expect(CallResult.fromJson({'timedOut': true}), isA<CallTimedOut>());
    expect(
      CallResult.fromJson({'refused': 'denied', 'reason': 'r'}),
      isA<CallRefused>(),
    );
  });

  test('a null value of a state that may be null is read with the rest', () {
    final r = Registry();
    final w = GeneratedWords(
      r.participant(owner, vocabularies: [WordSet.open('a')]),
    ).state(Maybe.level).define();
    w.set(null, key: 'a');
    w.set(3, key: 'b');
    expect(r.readAll(Maybe.level.name), {'a': null, 'b': 3});
  });

  test('a call whose asked guard took a while is refused when its command '
      'cannot run by then', () async {
    final r = Registry();
    String? why;
    r.defineCommand(
      CommandDescriptor('a.go', callers: Callers.only(['user'])),
      (_) {},
      available: () => why,
    );
    r.addAskedGuard('slow', (_) async {
      why = 'it stopped';
      return null;
    });
    final result = await r.call('a.go', {}, by: user);
    expect(
      result,
      isA<CallRefused>().having((x) => x.code, 'code', Refusal.unavailable),
    );
  });

  test('what follows a registry ends when it is disposed', () async {
    final r = Registry();
    r.defineState(StateDescriptor('a.x', type: const IntType()), by: owner);
    final watch = Completer<void>();
    final status = Completer<void>();
    final feed = Completer<void>();
    r.watch('a.x').listen((_) {}, onDone: watch.complete);
    r.statusChanges('a.x', by: user).listen((_) {}, onDone: status.complete);
    r.feed().listen((_) {}, onDone: feed.complete);
    await pump();
    await r.dispose();
    await Future.wait([
      watch.future,
      status.future,
      feed.future,
    ]).timeout(const Duration(seconds: 1));
  });

  test('a command takes a while to answer, not none', () {
    expect(
      () => CommandDescriptor(
        'a.go',
        callers: Callers.only(['user']),
        deadline: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}

enum Maybe<T> implements IStateWord<T> {
  level<int?>('a.maybe');

  const Maybe(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const NullableShape(PlainShape(IntType())) as Shape<T>;
  @override
  String? get key => 'input';
}
