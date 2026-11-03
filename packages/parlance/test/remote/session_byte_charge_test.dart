import 'dart:async';

import 'package:parlance/schema.dart';
import 'package:parlance/src/participant/local.dart' show Participants;
import 'package:parlance/src/registry/json.dart' show jsonWeight;
import 'package:parlance/src/registry/registry.dart' show Registry;
import 'package:parlance/src/remote/contract.dart';
import 'package:parlance/src/remote/session.dart'
    show ServeParticipant, SessionLimits;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// What the session byte bound must now cover: `define` descriptors, `kind`
/// entities and `emit` payloads — the three shapes a served guest feeds the
/// host with, each retained in host memory, none charged before round 3.
/// The caller is pinned to codec mode (L-1): the frames must arrive as
/// bytes and pass the host's request codec.
void main() {
  (ParlanceContractPeerCaller, Registry) serve(
    String who,
    String vocabulary,
    SessionLimits limits,
  ) {
    final opened = <RpcPeerEndpoint>[];
    addTearDown(() async {
      for (final e in opened) {
        await e.close();
      }
    });
    final (g, h) = RpcChannelTransport.memoryPair();
    final hostEp = RpcPeerEndpoint(transport: h);
    final registry = Registry();
    registry
        .participant(
          Principal('guest', who),
          vocabularies: [WordSet.open(vocabulary)],
        )
        .serve(hostEp, limits: limits);
    hostEp.start();
    final guestEp = RpcPeerEndpoint(transport: g)..start();
    opened.addAll([hostEp, guestEp]);
    return (
      ParlanceContractPeerCaller(
        guestEp,
        dataTransferMode: RpcDataTransferMode.codec,
      ),
      registry,
    );
  }

  Future<List<Map<String, Object?>>> apply(
    ParlanceContractPeerCaller guest,
    List<Map<String, Object?>> ops,
  ) async {
    final answer = await guest.apply(WireJson({'ops': ops}));
    return [
      for (final r in answer.json['results']! as List)
        r is Map ? r.cast<String, Object?>() : const <String, Object?>{},
    ];
  }

  Map<String, Object?> stateDescriptor(String name, Object? meta) => {
    'is': 'state',
    'name': name,
    'type': {'type': 'any'},
    'meta': ?meta,
  };

  test('the default byte bound stops fat words and kinds before the count '
      'limits do', () async {
    final (guest, _) = serve('a', 'a', const SessionLimits());
    // Paired controls: small content under default limits is not refused.
    await guest.define(WireDefine(stateDescriptor('a.s', null)));
    await guest.define(
      WireDefine({
        'is': 'fact',
        'name': 'a.f',
        'type': {'type': 'any'},
      }),
    );
    var defined = 0;
    Object? byteRefusal;
    for (var i = 0; i < 256 && byteRefusal == null; i++) {
      try {
        await guest.define(
          WireDefine(stateDescriptor('a.d$i', {'blob': 'x' * 32768})),
        );
        defined++;
      } on RpcStatusException catch (e) {
        byteRefusal = e;
      }
    }
    // Before round 3 all 256 defines passed: only the count limit could
    // fire. Now the byte bound fires first, with the session healthy.
    expect(byteRefusal, isA<RpcStatusException>());
    final refusal = byteRefusal! as RpcStatusException;
    expect(refusal.statusCode, RpcStatus.resourceExhausted);
    expect(refusal.message, contains('bytes'));
    expect(defined, greaterThan(0));
    expect(defined, lessThan(256));
    // The same ledger is full: a fat kind is refused too, not just words.
    final kind = await apply(guest, [
      {
        'op': 'kind',
        'name': 'a.k',
        'entities': [
          for (var i = 0; i < 10; i++)
            {
              'id': 'e$i',
              'meta': {'m': 'y' * 4096},
            },
        ],
      },
    ]);
    expect(kind.single['error'], 'resourceExhausted');
    await guest.describe(RpcNull());

    // Control: unbounded takes the byte bound off; the same shapes pass.
    final (free, _) = serve('b', 'b', SessionLimits.unbounded);
    for (var i = 0; i < 40; i++) {
      await free.define(
        WireDefine(stateDescriptor('b.d$i', {'blob': 'x' * 32768})),
      );
    }
    final freeKind = await apply(free, [
      {
        'op': 'kind',
        'name': 'b.k',
        'entities': [
          for (var i = 0; i < 10; i++)
            {
              'id': 'e$i',
              'meta': {'m': 'y' * 4096},
            },
        ],
      },
    ]);
    expect(freeKind.single, isNot(contains('error')));
  });

  test('emits charge the same ledger, and undefine and unkind give the '
      'bytes back', () async {
    // Fixture weights computed in code; the limit leaves room for the four
    // successful shapes and nothing of the fifth's size.
    const unit = 1500;
    final meta1 = {'b': 'x' * unit};
    final entities = [
      for (var i = 0; i < 3; i++)
        {
          'id': 'e$i',
          'meta': {'m': 'y' * unit},
        },
    ];
    final payload = {'p': 'z' * unit};
    final factWeight = jsonWeight({
      'is': 'fact',
      'name': 'c.f',
      'type': {'type': 'any'},
    });
    final wordWeight = jsonWeight(stateDescriptor('c.w1', meta1));
    final kindWeight = [
      for (final e in entities) jsonWeight(e),
    ].fold(0, (a, b) => a + b);
    final emitWeight = jsonWeight(payload);
    final (guest, registry) = serve(
      'c',
      'c',
      SessionLimits(
        stateBytes: factWeight + wordWeight + kindWeight + emitWeight + 128,
      ),
    );
    await guest.define(
      WireDefine({
        'is': 'fact',
        'name': 'c.f',
        'type': {'type': 'any'},
      }),
    );
    await guest.define(WireDefine(stateDescriptor('c.w1', meta1)));
    final kind = await apply(guest, [
      {'op': 'kind', 'name': 'c.k1', 'entities': entities},
    ]);
    expect(kind.single, isNot(contains('error')));
    final taken = await guest.emit(WireEmit(fact: 'c.f', payload: payload));
    expect(taken.taken, isTrue);
    // The ledger is as full as the limit allows: one more payload of the
    // same size is refused. Before round 3 it sailed.
    try {
      await guest.emit(WireEmit(fact: 'c.f', payload: payload));
      fail('the second payload was not refused');
    } on RpcStatusException catch (e) {
      expect(e.statusCode, RpcStatus.resourceExhausted);
    }
    // undefine gives the word's bytes back; the same size defines again.
    await guest.undefine(const WireName('c.w1'));
    expect(registry.stateDescriptor('c.w1'), isNull);
    await guest.define(WireDefine(stateDescriptor('c.w2', meta1)));
    // unkind gives the kind's bytes back; the same size kinds again.
    final unkind = await apply(guest, [
      {'op': 'unkind', 'name': 'c.k1'},
    ]);
    expect(unkind.single, isNot(contains('error')));
    final rekind = await apply(guest, [
      {'op': 'kind', 'name': 'c.k2', 'entities': entities},
    ]);
    expect(rekind.single, isNot(contains('error')));
    // A small payload still fits: the refusal was about bytes, not emits.
    final small = await guest.emit(WireEmit(fact: 'c.f', payload: {'p': 'z'}));
    expect(small.taken, isTrue);
  });
}
