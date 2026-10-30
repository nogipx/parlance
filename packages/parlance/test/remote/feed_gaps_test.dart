import 'package:parlance/src/participant/local.dart' show Participants;
import 'package:parlance/src/remote/client.dart';
import 'package:parlance/src/remote/mirror.dart';
import 'package:parlance/tools.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// What a guest hears across a connection, and what it is told when it
/// cannot: a fact said once it settled is heard; facts gone past what the
/// host retains are told (`factsLost`), not passed over in silence; and a
/// copy that lost the registry stops waiting rather than answer late.
const house = Principal('house');
const guest = Principal('guest');

void main() {
  late Registry r;
  late List<ParticipantError> errors;
  late RemoteParticipant p;
  late RpcClientConnection connection;
  late List<RpcPeerEndpoint> hosts;
  late IFactHandle rang;

  setUp(() async {
    r = Registry(limits: const HostLimits(retainTicks: 2));
    rang = r
        .participant(house, vocabularies: [WordSet.open('house')])
        .defineFact(
          FactDescriptor(
            'house.rang',
            type: const IntType(),
            readers: Callers.anyone,
          ),
        );
    errors = [];
    hosts = [];
    connection = RpcClientConnection(
      transportFactory: (_) async {
        final (c, s) = RpcChannelTransport.memoryPair();
        final h = RpcPeerEndpoint(transport: s);
        r.participant(guest).serve(h);
        h.start();
        hosts.add(h);
        return c;
      },
      backoff: const RpcFixedBackoff(Duration(milliseconds: 20)),
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

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('a fact said right after it listens and settles is heard', () async {
    final heard = <Object?>[];
    p.facts('house.rang').listen((f) => heard.add(f.payload));
    await p.settle();
    rang.say(1);
    await until(() => heard.isNotEmpty);
    expect(heard, [1]);
  });

  test('facts said while it was away, past what the host retains, are '
      'told lost', () async {
    final heard = <Object?>[];
    p.facts('house.rang').listen((f) => heard.add(f.payload));
    await p.settle();
    await hosts.last.close();
    for (var i = 1; i <= 10; i++) {
      rang.say(i);
    }
    await until(
      () => errors.any((e) => e.code == ParticipantErrorCode.factsLost),
    );
    expect(
      errors.map((e) => (e.op['op'], e.code)),
      contains(('feed', ParticipantErrorCode.factsLost)),
    );
    expect(heard, isNot(contains(1)), reason: 'those facts are gone');
  });

  test('a copy that loses the registry stops waiting to reach a seq, as '
      'its synced says', () async {
    final mirror = RegistryMirror();
    addTearDown(mirror.dispose);
    final (c, s) = RpcChannelTransport.memoryPair();
    final h = RpcPeerEndpoint(transport: s);
    r.participant(const Principal('viewer')).serve(h);
    h.start();
    mirror.follow(ParlanceClient(RpcPeerEndpoint(transport: c)..start()));
    await mirror.changes.firstWhere((_) => mirror.synced);
    final waiting = mirror.reach(r.epoch, r.seq + 5);
    await h.close();
    expect(await waiting.timeout(const Duration(seconds: 1)), isFalse);
    expect(mirror.synced, isFalse);
  });
}
