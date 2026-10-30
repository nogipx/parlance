import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/contract.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

const host = Principal('host');
const visitor = Principal('visitor', 'slow');

void main() {
  late Registry r;
  late RemoteSession session;
  late RpcPeerEndpoint endpoint;

  Future<void> open({required int retainTicks}) async {
    r = Registry(retainTicks: retainTicks);
    final (_, s) = RpcChannelTransport.memoryPair();
    endpoint = RpcPeerEndpoint(transport: s);
    session = r.participant(visitor).serve(endpoint, feedBacklog: 4);
  }

  tearDown(() async {
    session.dispose();
    await endpoint.close();
    r.dispose();
  });

  /// A client that takes nothing while [writes] run, then all.
  Future<List<WireFeedItem>> slowly(Future<void> Function() writes) async {
    final got = <WireFeedItem>[];
    final sub = session.onFeed(const WireFeedRequest()).listen(got.add);
    await pumpEventQueue();
    sub.pause();
    await writes();
    sub.resume();
    await pumpEventQueue();
    await sub.cancel();
    return got;
  }

  Future<void> count(int n) async {
    final p = r.participant(host, vocabularies: [WordSet.open('count')]);
    final at = p.defineState(
      StateDescriptor(
        'count.at',
        type: const IntType(),
        readers: Callers.anyone,
      ),
    );
    final said = p.defineFact(
      FactDescriptor(
        'count.said',
        type: const IntType(),
        readers: Callers.anyone,
      ),
    );
    for (var i = 1; i <= n; i++) {
      p.batch(() {
        at.set(i);
        said.say(i);
      });
      await pumpEventQueue();
    }
  }

  test('a slow client is fed again from the last tick it took, as the '
      'registry still has it: no gap, nothing lost', () async {
    await open(retainTicks: 1000);
    final got = await slowly(() => count(20));
    final ticks = [
      for (final i in got)
        if (i.kind == 'tick') Tick.fromJson(i.json),
    ];
    final snapshot = Snapshot.fromJson(
      got.firstWhere((i) => i.kind == 'snapshot').json,
    );
    var seq = snapshot.seq;
    for (final t in ticks) {
      expect(t.from, seq + 1, reason: 'no gap');
      seq = t.to;
    }
    expect(
      [for (final t in ticks) ...t.facts.map((f) => f.payload)],
      [for (var i = 1; i <= 20; i++) i],
    );
    expect(ticks.last.changes.single.value, 20);
  });

  test('when the registry no longer has those ticks, a snapshot of now '
      'follows, saying facts were lost', () async {
    await open(retainTicks: 2);
    final got = await slowly(() => count(20));
    final last = Snapshot.fromJson(
      got.lastWhere((i) => i.kind == 'snapshot').json,
    );
    expect(last.factsLost, isTrue);
    expect(last.states['count.at']!.values.single, 20);
    expect(
      got.where((i) => i.kind == 'tick').length,
      lessThan(20),
      reason: 'what it held past its backlog went',
    );
  });
}
