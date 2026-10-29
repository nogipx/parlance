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
  void define(IParticipant p) {
    keep(
      p.defineState(StateDescriptor('lamp.on', type: const BoolType())),
    ).set(true);
  }
}

void main() {
  late Registry r;
  late LocalParticipant studio;
  late IStateHandle program;
  final opened = <RpcPeerEndpoint>[];
  setUp(() {
    r = Registry();
    studio = r.participant(
      const Principal('studio'),
      vocabularies: [WordSet.open('studio')],
    );
    program = studio.defineState(
      StateDescriptor('studio.program', type: const IntType()),
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
      p.watch('studio.program').listen(seen.add);
      await p.settle();
      program.set(7);
      await p.settle();
      expect(p.read('studio.program'), 7);
      expect(seen.last, 7);
    },
  );

  test('settle waits for nothing more when the copy follows only some '
      'words', () async {
    final p = await join();
    p.watch('studio.program').listen((_) {});
    await p.settle();
    final other = studio.defineState(
      StateDescriptor('studio.other', type: const IntType()),
    );
    for (var i = 0; i < 5; i++) {
      other.set(i);
    }
    final took = Stopwatch()..start();
    await p.settle();
    expect(took.elapsed, lessThan(const Duration(milliseconds: 500)));
  });
}
