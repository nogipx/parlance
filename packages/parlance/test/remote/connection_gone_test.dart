import 'package:parlance/tools.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// A session ends when its connection goes (SPEC §14): the transport
/// ends then, and the session with it, its words going, with no host code
/// closing it.
void main() {
  for (final wire in [false, true]) {
    test(
      'the connection gone, the session ends (${wire ? 'wire' : 'memory'})',
      () async {
        final r = Registry();
        addTearDown(r.dispose);
        final (g, h) = wire
            ? RpcChannelTransport.pair()
            : RpcChannelTransport.memoryPair();
        final host = RpcPeerEndpoint(transport: h);
        r
            .participant(
              const Principal('widlet', 'a'),
              vocabularies: [WordSet.open('lamp')],
            )
            .serve(host);
        host.start();
        final own = RpcPeerEndpoint(transport: g)..start();
        final p = await RemoteParticipant.over(own);
        p.defineState(StateDescriptor('lamp.on', type: const BoolType()));
        await p.flush();
        expect(r.stateDescriptor('lamp.on'), isNotNull);

        await own.close();
        for (var i = 0; i < 50 && r.stateDescriptor('lamp.on') != null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(r.stateDescriptor('lamp.on'), isNull, reason: 'its words went');
        // A new guest of that vocabulary is no longer refused.
        expect(
          () => r.participant(
            const Principal('widlet', 'b'),
            vocabularies: [WordSet.open('lamp')],
          ),
          returnsNormally,
        );
        await p.close();
        await host.close();
      },
    );
  }
}
