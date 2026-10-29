import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/src/remote/contract.dart'
    show parlanceFeatures, parlanceProtocol;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// The protocol grows by features, not by its major (SPEC §14): a host
/// tells what it speaks, a participant uses only that, and refuses to join
/// only a host that lacks what it requires. Guests over the air are often
/// built against a newer parlance than their host.
enum Built<T> implements IStateWord<T> {
  volume<int>('deck.volume', Plain(IntType(max: 100)));

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
        .defineState(StateDescriptor('deck.volume', type: const IntType()));
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
    return RemoteParticipant.over(own, requires: requires);
  }

  test('a host tells its major and every feature it speaks', () async {
    final p = await join();
    final d = await p.describe();
    expect(d['protocol'], parlanceProtocol);
    expect({...d['features']! as List}, parlanceFeatures);
  });

  test('a host without a feature a guest requires is refused, saying '
      'which', () async {
    await expectLater(
      join(features: const {}, requires: {'built'}),
      throwsA(
        isA<ProtocolMismatch>()
            .having((e) => e.missing, 'missing', {'built'})
            .having((e) => '$e', 'says', contains('does not speak built')),
      ),
    );
  });

  test('a guest uses what the host does not speak not at all, and works '
      'on', () async {
    final errors = <ParticipantError>[];
    final p = await join(features: const {});
    p.errors.listen(errors.add);
    p.builtAgainst(Built.values);
    await p.flush();
    expect(r.mismatches, isEmpty, reason: 'nothing told an older host');
    expect(errors, isEmpty);
    expect(p.status('deck.volume'), const WordReady());
    await p.close();
  });

  test('a host that speaks it is told', () async {
    final p = await join();
    p.builtAgainst(Built.values);
    await p.flush();
    expect(r.mismatches.single.word, 'deck.volume');
    await p.close();
  });

  test('a feature a guest does not know is passed over', () async {
    final p = await join(features: {...parlanceFeatures, 'grease-zz'});
    p.builtAgainst(Built.values);
    await p.flush();
    expect(r.mismatches, hasLength(1));
    await p.close();
  });
}
