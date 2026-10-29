import 'dart:async';

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/src/remote/contract.dart';
import 'package:parlance/src/remote/client.dart' show ParlanceClient;
import 'package:parlance/src/remote/mirror.dart' show RegistryMirror;
import 'package:parlance/testing.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/owner.dart' show Owner;
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const plugin = Principal('plugin', 'p');
const visitor = Principal('visitor', 'v');

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

/// A session served on an endpoint nobody calls: its handlers are called
/// here directly.
RemoteSession _session(Registry r, {Principal who = plugin}) {
  final (_, t) = RpcChannelTransport.memoryPair();
  return r
      .participant(who, vocabularies: [const WordSet.open('plug')])
      .serve(RpcPeerEndpoint(transport: t));
}

final class Ticking extends Owner {
  final changed = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => changed.stream;

  @override
  void define(IRawParticipant p) {}
}

void main() {
  test('a remote participant withdraws its state: whoever followed it is '
      'told it went', () async {
    final host = TestHost();
    addTearDown(host.dispose);
    final seen = <Object?>[];
    host.registry.watch('plug.level').listen(seen.add);
    final p = await host.join(
      plugin,
      vocabularies: [const WordSet.open('plug')],
    );
    final other = await host.join(visitor);
    final h = p.defineState(
      StateDescriptor('plug.level', type: const IntType()),
    );
    h.set(5);
    await host.settle();
    final there = <Object?>[];
    other.watch('plug.level').listen(there.add);
    await host.settle();

    h.dispose();
    await host.settle();

    expect(seen, [null, 5, null]);
    expect(there.last, isNull);
    expect(other.read('plug.level'), isNull);
  });

  test(
    'an op that is no op is refused alone; the ops around it stand',
    () async {
      final r = Registry();
      final s = _session(r);
      await s.onApply(
        const WireJson({
          'ops': [
            {
              'op': 'define',
              'descriptor': {
                'is': 'state',
                'name': 'plug.v',
                'type': {'type': 'int'},
              },
            },
          ],
        }),
      );
      final answer = await s.onApply(
        const WireJson({
          'ops': [
            {'op': 'set', 'state': 'plug.v', 'value': 1},
            {'op': 'kind', 'name': 'Not A Name', 'entities': <Object?>[]},
            {'op': 'set', 'state': 'plug.v', 'value': 2, 'as': 7},
          ],
        }),
      );
      final results = answer.json['results']! as List;
      expect(results[0], isEmpty);
      expect((results[1] as Map)['error'], 'invalidArgument');
      expect((results[2] as Map)['error'], 'invalidArgument');
      expect(r.read('plug.v'), 1);
      s.close();
    },
  );

  test('a session that ends ends its feeds', () async {
    final r = Registry();
    final other = r.defineState(
      StateDescriptor('host.n', type: const IntType()),
      by: const Principal('host'),
    );
    final s = _session(r);
    final kinds = <String>[];
    final ended = Completer<void>();
    s
        .onFeed(const WireFeedRequest())
        .listen((i) => kinds.add(i.kind), onDone: ended.complete);
    await pump();
    s.close();
    await ended.future.timeout(const Duration(seconds: 1));
    final before = kinds.length;
    other.set(3);
    await pump();
    expect(kinds.length, before);
  });

  test(
    'a feed asked from a seq of another run starts with a snapshot',
    () async {
      final r = Registry();
      r
          .defineState(
            StateDescriptor('host.n', type: const IntType()),
            by: const Principal('host'),
          )
          .set(1);
      await pump();
      final s = _session(r);
      final kinds = <String>[];
      final sub = s
          .onFeed(WireFeedRequest(epoch: 'another run', since: r.seq))
          .listen((i) => kinds.add(i.kind));
      await pump();
      expect(kinds.take(2), ['catalog', 'snapshot']);
      await sub.cancel();
      s.close();
    },
  );

  test(
    'a mirror lets go the values of a state the catalog no longer has',
    () async {
      final r = Registry();
      r
          .defineState(
            StateDescriptor('host.n', type: const IntType()),
            by: const Principal('host'),
          )
          .set(1);
      final (c, t) = RpcChannelTransport.memoryPair();
      final responder = RpcPeerEndpoint(transport: t);
      final s = r.participant(visitor).serve(responder);
      responder.start();
      final caller = RpcPeerEndpoint(transport: c)..start();
      final mirror = RegistryMirror()..follow(ParlanceClient(caller));
      await pump();
      expect(mirror.read('host.n'), 1);
      mirror.takeCatalog(const {'descriptors': <Object?>[]});
      expect(mirror.read('host.n'), isNull);
      await mirror.dispose();
      s.close();
      await caller.close();
      await responder.close();
    },
  );

  test('a call as someone the session is not is refused, not lost', () async {
    final r = Registry();
    final (c, t) = RpcChannelTransport.memoryPair();
    final responder = RpcPeerEndpoint(transport: t);
    final s = r.participant(visitor).serve(responder);
    responder.start();
    final caller = RpcPeerEndpoint(transport: c)..start();
    final answer = await ParlanceClient(
      caller,
    ).callAt('host.go', const {}, as: const Principal('user', 'local'));
    expect(
      answer.result,
      isA<CallRefused>().having((x) => x.code, 'code', Refusal.notPermitted),
    );
    s.close();
    await caller.close();
    await responder.close();
  });

  test('a call as no principal at all is refused as such, not lost', () async {
    final r = Registry();
    final (c, t) = RpcChannelTransport.memoryPair();
    final responder = RpcPeerEndpoint(transport: t);
    final s = r.participant(visitor).serve(responder);
    responder.start();
    final caller = RpcPeerEndpoint(transport: c)..start();
    final answer = await ParlanceClient(
      caller,
    ).callAt('host.go', const {}, as: const Principal('Not A Kind'));
    expect(answer.result, isA<CallFailed>());
    s.close();
    await caller.close();
    await responder.close();
  });

  test('a participant whose words were all withdrawn can be served', () {
    final r = Registry();
    final fresh = r.participant(
      plugin,
      vocabularies: [const WordSet.open('plug')],
    );
    fresh
        .defineState(StateDescriptor('plug.x', type: const IntType()))
        .dispose();
    fresh.addGuard('g', (_) => null).dispose();
    final (_, t) = RpcChannelTransport.memoryPair();
    expect(
      () => fresh.serve(RpcPeerEndpoint(transport: t)).close(),
      returnsNormally,
    );
  });

  test('the owners of a remote participant go with it', () async {
    final host = TestHost();
    addTearDown(host.dispose);
    final p = await host.join(
      plugin,
      vocabularies: [const WordSet.open('plug')],
    );
    final owner = Ticking();
    p.attach({'tick': owner});
    expect(owner.changed.hasListener, isTrue);
    await p.close();
    expect(owner.changed.hasListener, isFalse);
  });
}
