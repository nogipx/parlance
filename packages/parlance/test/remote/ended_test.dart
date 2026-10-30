import 'package:parlance/tools.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/local.dart' show Participants;

/// A session `main` ends, its connection still up, tells the part across
/// why (SPEC §14): it hears it as `lost` and does not join again, rather
/// than ask a session that is gone for good.
const kittens = Principal('plugin', 'kittens');

void main() {
  late Registry r;
  late List<ParticipantError> errors;
  late RemoteParticipant p;
  late RemoteSession session;
  late RpcClientConnection connection;
  late List<RpcPeerEndpoint> hosts;

  setUp(() async {
    r = Registry();
    errors = [];
    hosts = [];
    connection = RpcClientConnection(
      transportFactory: (_) async {
        final (c, s) = RpcChannelTransport.memoryPair();
        final h = RpcPeerEndpoint(transport: s);
        session = r
            .participant(kittens, vocabularies: [WordSet.open('kittens')])
            .serve(h);
        h.start();
        hosts.add(h);
        return c;
      },
      backoff: const RpcFixedBackoff(Duration(milliseconds: 10)),
    );
    p = await RemoteParticipant.join(
      connection,
      onParticipantError: errors.add,
    );
  });

  tearDown(() async {
    await p.dispose();
    await connection.dispose();
    for (final h in hosts) {
      await h.close();
    }
    await r.dispose();
  });

  Future<void> told() async {
    for (var i = 0; i < 50 && errors.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('a session closed by main is told, and not joined again', () async {
    final lamp = p.defineState(
      StateDescriptor('kittens.lamp', type: const BoolType()),
    );
    lamp.set(false);
    await p.flush();

    session.dispose();
    await told();
    expect(errors.single.code, ParticipantErrorCode.lost);
    expect(errors.single.op['op'], 'join');
    expect(errors.single.why, contains('closed'));

    lamp.set(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(r.stateDescriptor('kittens.lamp'), isNull, reason: 'its words went');
    expect(hosts, hasLength(1), reason: 'it did not join again');
  });

  test('a session taken over is told', () async {
    final (_, s) = RpcChannelTransport.memoryPair();
    r
        .participant(kittens, vocabularies: [WordSet.open('kittens')])
        .serve(RpcPeerEndpoint(transport: s));
    await told();
    expect(errors.single.code, ParticipantErrorCode.lost);
    expect(errors.single.why, contains('took its place'));
  });
}
