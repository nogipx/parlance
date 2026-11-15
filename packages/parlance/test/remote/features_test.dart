import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/contract.dart'
    show parlanceFeatures, parlanceProtocol;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/local.dart' show Participants;

/// Current peers share one required wire baseline (SPEC §14).
enum Built<T> implements IStateWord<T> {
  volume<int>('deck.volume', PlainShape(IntType(max: 100)));

  const Built(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

const guest = Principal('widlet', 'b');

void main() {
  late Registry r;
  final opened = <RpcPeerEndpoint>[];

  setUp(() {
    r = Registry();
    // The volume as its owner defines it now: past what code reads.
    r
        .participant(
          const Principal('deck'),
          vocabularies: [WordSet.open('deck')],
        )
        .defineState(
          StateDescriptor('deck/deck.volume', type: const IntType()),
        );
  });
  tearDown(() async {
    for (final e in opened) {
      await e.close();
    }
    opened.clear();
    await r.dispose();
  });

  /// A guest joining a host that tells it speaks [features].
  Future<RemoteParticipant> join({
    Set<String>? features,
    Set<String> requires = const {},
  }) async {
    final (g, h) = RpcChannelTransport.pair();
    final host = RpcPeerEndpoint(transport: h);
    r.participant(guest).serve(host, features: features);
    host.start();
    final own = RpcPeerEndpoint(transport: g)..start();
    opened.addAll([host, own]);
    return RemoteParticipant.joinEndpoint(own, requires: requires);
  }

  test('a host tells its major and every feature it speaks', () async {
    final p = await join();
    final d = await p.describe();
    expect(d['protocol'], parlanceProtocol);
    expect({...d['features']! as List}, parlanceFeatures);
  });

  for (final feature in parlanceFeatures) {
    test('joining refuses a host missing $feature', () async {
      await expectLater(
        join(features: {...parlanceFeatures}..remove(feature)),
        throwsA(
          isA<ProtocolMismatch>().having((e) => e.missing, 'missing', {
            feature,
          }),
        ),
      );
      expect(r.mismatches, isEmpty);
    });
  }

  test('additional application requirements are enforced', () async {
    await expectLater(
      join(requires: {'extension'}),
      throwsA(
        isA<ProtocolMismatch>().having((e) => e.missing, 'missing', {
          'extension',
        }),
      ),
    );
  });

  test('a host that speaks it is told', () async {
    final p = await join();
    p.builtAgainst(Built.values, target: const Principal('deck'));
    await p.flush();
    expect(r.mismatches.single.word, 'deck/deck.volume');
    await p.dispose();
  });

  test('a feature a guest does not know is passed over', () async {
    final p = await join(features: {...parlanceFeatures, 'grease-zz'});
    p.builtAgainst(Built.values, target: const Principal('deck'));
    await p.flush();
    expect(r.mismatches, hasLength(1));
    await p.dispose();
  });
}
