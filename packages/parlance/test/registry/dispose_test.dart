import 'package:parlance/schema.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/client.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/local.dart' show Participants;

part 'dispose_test.g.dart';

/// A registry disposed ends what holds it, the last made first: its
/// participants, their owners, and the sessions it serves. Nothing is
/// closed by hand before it.
@Vocabulary('lamp')
abstract class Lamp {
  @StateWord('on')
  bool get on;
}

final class _Lamp extends LampOwnerBase {
  _Lamp() {
    onDispose(() => gone = true);
  }

  var gone = false;
}

void main() {
  test(
    'dispose ends its participants, their owners and its sessions',
    () async {
      final r = Registry();
      final lamp = _Lamp();
      final p = r.participant(const Principal('lamp'), owners: [lamp]);
      final (g, h) = RpcChannelTransport.memoryPair();
      final host = RpcPeerEndpoint(transport: h);
      r.participant(const Principal('widlet', 'a')).serve(host);
      host.start();
      final own = RpcPeerEndpoint(transport: g)..start();
      final client = ParlanceClient(own);
      expect(await client.describe(), isNotEmpty);

      await r.dispose();
      expect(lamp.gone, isTrue);
      expect(
        () => p.defineState(StateDescriptor('lamp.x', type: const IntType())),
        throwsStateError,
      );
      await expectLater(
        client.describe(),
        throwsA(
          isA<RpcStatusException>().having(
            (e) => e.statusCode,
            'status',
            RpcStatus.unavailable,
          ),
        ),
      );
      await own.close();
      await host.close();
    },
  );
}
