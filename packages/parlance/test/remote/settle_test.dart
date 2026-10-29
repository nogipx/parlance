import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// What a guest waits for, with no delay of its own: `attach` until the
/// host has its owners' words, `settle` until its copy and its listeners
/// are as the host is.
final class _Lamp extends Owner {
  @override
  void define(IRawParticipant p) {
    keep(
      p.defineState(StateDescriptor('lamp.on', type: const BoolType())),
    ).set(true);
  }
}

void main() {
  late Registry r;
  late LocalParticipant house;
  late IStateHandle focus;
  final opened = <RpcPeerEndpoint>[];
  setUp(() {
    r = Registry();
    house = r.participant(
      const Principal('house'),
      vocabularies: [WordSet.open('house')],
    );
    focus = house.defineState(
      StateDescriptor('house.focus', type: const IntType()),
    );
  });
  tearDown(() async {
    for (final e in opened) {
      await e.close();
    }
    opened.clear();
    await r.dispose();
  });

  Future<RemoteParticipant> join() async {
    final (g, h) = RpcChannelTransport.memoryPair();
    final host = RpcPeerEndpoint(transport: h);
    r
        .participant(
          const Principal('widlet', 'a'),
          vocabularies: [WordSet.open('lamp')],
        )
        .serve(host);
    host.start();
    final own = RpcPeerEndpoint(transport: g)..start();
    opened.addAll([host, own]);
    final p = await RemoteParticipant.over(own);
    addTearDown(p.close);
    return p;
  }

  test(
    'attach completes when the host has the words and their values',
    () async {
      final p = await join();
      await p.attach({'it': _Lamp()});
      expect(r.read('lamp.on'), isTrue);
    },
  );

  test(
    'settle: the copy is as the host is, and its listeners were told',
    () async {
      final p = await join();
      final seen = <Object?>[];
      p.watch('house.focus').listen(seen.add);
      await p.settle();
      focus.set(7);
      await p.settle();
      expect(p.read('house.focus'), 7);
      expect(seen.last, 7);
    },
  );

  test('settle waits for nothing more when the copy follows only some '
      'words', () async {
    final p = await join();
    p.watch('house.focus').listen((_) {});
    await p.settle();
    final other = house.defineState(
      StateDescriptor('house.other', type: const IntType()),
    );
    for (var i = 0; i < 5; i++) {
      other.set(i);
    }
    final took = Stopwatch()..start();
    await p.settle();
    expect(took.elapsed, lessThan(const Duration(milliseconds: 500)));
  });
}
