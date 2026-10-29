import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// A part across a connection may be another's code, or code with a
/// defect: a session bounds what it holds of the host's (SPEC §14). What
/// it asks past a bound is refused, `resourceExhausted`, and what it holds
/// stays; a call past its calls in flight runs nowhere.
const guest = Principal('widlet', 'g');

void main() {
  late Registry r;
  final opened = <RpcPeerEndpoint>[];
  setUp(() => r = Registry());
  tearDown(() async {
    for (final e in opened) {
      await e.close();
    }
    opened.clear();
    await r.dispose();
  });

  Future<(RemoteParticipant, List<ParticipantError>)> join(
    SessionLimits limits,
  ) async {
    final (g, h) = RpcChannelTransport.memoryPair();
    final host = RpcPeerEndpoint(transport: h);
    r
        .participant(guest, vocabularies: [WordSet.open('notes')])
        .serve(host, limits: limits);
    host.start();
    final own = RpcPeerEndpoint(transport: g)..start();
    opened.addAll([host, own]);
    final errors = <ParticipantError>[];
    final p = await RemoteParticipant.over(own, onError: errors.add);
    addTearDown(p.close);
    return (p, errors);
  }

  test('a keyed state it never empties stops at its bytes; one removed '
      'makes room', () async {
    final (p, errors) = await join(const SessionLimits(stateBytes: 200));
    final seen = p.defineState(
      StateDescriptor('notes.seen', type: const TextType(), key: 'visitor'),
    );
    for (var i = 0; i < 20; i++) {
      seen.set('x' * 20, key: 'v$i');
    }
    await p.flush();
    final held = r.readAll('notes.seen');
    expect(held, isNotEmpty);
    expect(held.length, lessThan(20));
    expect(errors.map((e) => e.code).toSet(), {'resourceExhausted'});
    seen.remove(key: 'v0');
    seen.set('x' * 20, key: 'new');
    await p.flush();
    expect(r.read('notes.seen', key: 'new'), 'x' * 20);
  });

  test('so many words and no more; one withdrawn makes room', () async {
    final (p, errors) = await join(const SessionLimits(words: 2));
    p.defineState(StateDescriptor('notes.a', type: const IntType()));
    final b = p.defineState(StateDescriptor('notes.b', type: const IntType()));
    p.defineState(StateDescriptor('notes.c', type: const IntType()));
    await p.flush();
    expect(r.stateDescriptor('notes.c'), isNull);
    expect(errors.single.code, 'resourceExhausted');
    b.dispose();
    p.defineState(StateDescriptor('notes.d', type: const IntType()));
    await p.flush();
    expect(r.stateDescriptor('notes.d'), isNotNull);
  });

  test('so many guards and no more', () async {
    final (p, errors) = await join(const SessionLimits(guards: 1));
    p.addGuard('one', (_) => null);
    p.addGuard('two', (_) => null);
    await p.flush();
    expect(errors.single.code, 'resourceExhausted');
    expect(errors.single.message, contains('1 guards'));
  });

  test('so many entities in its kinds and no more', () async {
    final (p, errors) = await join(const SessionLimits(entities: 2));
    p.registerKind(
      EntityKind('note', list: () => const [EntityRef('a'), EntityRef('b')]),
    );
    p.registerKind(EntityKind('tag', list: () => const [EntityRef('t')]));
    await p.flush();
    expect(r.hasKind('note'), isTrue);
    expect(r.hasKind('tag'), isFalse);
    expect(errors.single.code, 'resourceExhausted');
  });

  test('a call past its calls in flight runs nowhere and says why; one '
      'answered makes room', () async {
    final gate = Completer<void>();
    var ran = 0;
    r
        .participant(
          const Principal('deck'),
          vocabularies: [WordSet.open('deck')],
        )
        .defineCommand(
          CommandDescriptor('deck.slow', callers: Callers.only(['widlet'])),
          (_) async {
            ran++;
            await gate.future;
          },
        );
    final (p, _) = await join(const SessionLimits(calls: 1));
    final first = p.call('deck.slow', {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = await p.call('deck.slow', {});
    expect(
      second,
      isA<CallRefused>()
          .having((c) => c.code, 'code', Refusal.unavailable)
          .having((c) => c.reason, 'reason', contains('1 calls')),
    );
    gate.complete();
    expect(await first, isA<CallDone<Object?>>());
    expect(await p.call('deck.slow', {}), isA<CallDone<Object?>>());
    expect(ran, 2);
  });

  test('none bounds nothing', () async {
    final (p, errors) = await join(SessionLimits.none);
    for (var i = 0; i < 300; i++) {
      p.defineState(StateDescriptor('notes.s$i', type: const IntType()));
    }
    await p.flush();
    expect(errors, isEmpty);
    expect(r.stateDescriptor('notes.s299'), isNotNull);
  });
}
