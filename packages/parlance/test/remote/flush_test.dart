import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/local.dart' show Participants;

/// A flush waits for what was asked before it (SPEC §22.4), not for what
/// comes after: none is left waiting behind the writes that follow it.
void main() {
  late Registry r;
  late RemoteParticipant p;
  final opened = <RpcPeerEndpoint>[];
  setUp(() async {
    r = Registry();
    final (g, h) = RpcChannelTransport.memoryPair();
    final host = RpcPeerEndpoint(transport: h);
    r
        .participant(
          const Principal('widlet', 'a'),
          vocabularies: [WordSet.open('ga')],
        )
        .serve(host);
    host.start();
    final own = RpcPeerEndpoint(transport: g)..start();
    opened.addAll([host, own]);
    p = await RemoteParticipant.joinEndpoint(own);
  });
  tearDown(() async {
    await p.close();
    for (final e in opened) {
      await e.close();
    }
    opened.clear();
    await r.dispose();
  });

  test('a flush ends once what it asked is answered, though each answer '
      'is followed at once by another write', () async {
    final level = p.defineState(
      StateDescriptor('ga.level', type: const IntType()),
    );
    await p.flush();
    var answered = 0;
    level.set(0);
    final first = p.flush();
    // Asked while the first send goes: it waits for that one alone.
    int? endedAfter;
    final second = p.flush().then((_) => endedAfter = answered);
    Future<void> chain(Future<void> f, int left) => f.then((_) {
      answered++;
      if (left == 0) return null;
      level.set(answered);
      return chain(p.flush(), left - 1);
    });
    await chain(first, 20);
    await second;
    expect(endedAfter, lessThanOrEqualTo(2), reason: 'not after all 21');
    expect(r.read('ga.level'), 20);
  });
}
