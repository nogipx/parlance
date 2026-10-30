import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// A part whose connection went without its host seeing it (a link half
/// open) comes back before its old session ends: the new session of the
/// same principal takes the old one's place, as an MQTT broker takes a
/// client's session over (SPEC §14). Another principal is refused as
/// before.
const kittens = Principal('plugin', 'kittens');

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late Registry r;
  setUp(() => r = Registry());
  tearDown(() => r.dispose());

  test('a part back before its old session ended takes its place', () async {
    final sessions = <RemoteSession>[];
    final hosts = <RpcPeerEndpoint>[];
    final connection = RpcClientConnection(
      transportFactory: (_) async {
        final (c, s) = RpcChannelTransport.memoryPair();
        final h = RpcPeerEndpoint(transport: s);
        sessions.add(
          r
              .participant(kittens, vocabularies: [WordSet.open('kittens')])
              .serve(h),
        );
        h.start();
        hosts.add(h);
        return c;
      },
      backoff: const RpcFixedBackoff(Duration(milliseconds: 10)),
    );
    final p = await RemoteParticipant.join(connection);
    final lamp = p.defineState(
      StateDescriptor('kittens.lamp', type: const BoolType()),
    );
    lamp.set(false);
    await p.flush();
    expect(r.read('kittens.lamp'), false);

    // The link goes; the host does not see it, and ends no session.
    final offline = connection.state.firstWhere((s) => s is! RpcClientOnline);
    await hosts.last.close();
    await offline;
    lamp.set(true);

    final back = DateTime.now().add(const Duration(seconds: 5));
    while (r.read('kittens.lamp') != true && DateTime.now().isBefore(back)) {
      await settle();
    }
    expect(sessions, hasLength(2), reason: 'it came back');
    expect(r.read('kittens.lamp'), true, reason: 'its word, as it stands');

    // The host sees the old link go at last: the new session stays.
    sessions.first.dispose();
    await settle();
    expect(r.read('kittens.lamp'), true);

    await p.close();
    await connection.dispose();
    for (final s in sessions) {
      s.dispose();
    }
  });

  test("another principal's session is not taken over", () {
    final (_, s) = RpcChannelTransport.memoryPair();
    r
        .participant(kittens, vocabularies: [WordSet.open('kittens')])
        .serve(RpcPeerEndpoint(transport: s));
    expect(
      () => r.participant(
        const Principal('plugin', 'other'),
        vocabularies: [WordSet.open('kittens')],
      ),
      throwsA(isA<NotPermitted>()),
    );
  });

  test('a participant in this process is not taken over, served by no '
      'session', () {
    r.participant(kittens, vocabularies: [WordSet.open('kittens')]);
    expect(
      () => r.participant(kittens, vocabularies: [WordSet.open('kittens')]),
      throwsA(isA<NotPermitted>()),
    );
  });
}
