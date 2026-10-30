import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/client.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/owner.dart' show Owner;

/// A registry disposed ends what holds it, the last made first: its
/// participants, their owners and parts, and the sessions it serves.
/// Nothing is closed by hand before it.
final class _Lamp extends Owner {
  late final IStateWriterOf<bool> on;
  var gone = false;

  @override
  void define(IRawParticipant p) {
    on = keep(p.state(_On.on).define());
  }

  @override
  void dispose() {
    gone = true;
    super.dispose();
  }
}

enum _On<T> implements IStateWord<T> {
  on<bool>('lamp.on', Plain(BoolType()));

  const _On(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

void main() {
  test(
    'dispose ends its participants, their owners and its sessions',
    () async {
      final r = Registry();
      final p = r.participant(
        const Principal('lamp'),
        vocabularies: [WordSet.open('lamp')],
      );
      final lamp = _Lamp();
      await p.attach([lamp]);
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
