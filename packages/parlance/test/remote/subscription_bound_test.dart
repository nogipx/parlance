import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/client.dart' show ParlanceClient;
import 'package:parlance/src/remote/mirror.dart' show RegistryMirror;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/local.dart' show Participants;

/// What a session carries for a participant is bounded (SPEC §12, §14):
/// asked past the bound, it carries everything rather than leave some of
/// what was asked out, and the participant says so. And a call answered in
/// a run of the registry its copy has left waits for nothing.
void main() {
  final opened = <RpcPeerEndpoint>[];
  final registries = <Registry>[];
  tearDown(() async {
    for (final e in opened) {
      await e.close();
    }
    opened.clear();
    for (final r in registries) {
      await r.dispose();
    }
    registries.clear();
  });

  /// A registry whose deck holds [states], each its number.
  Registry deckOf(List<String> states) {
    final r = Registry();
    registries.add(r);
    final deck = r.participant(
      const Principal('deck'),
      vocabularies: [WordSet.open('deck')],
    );
    for (final (i, s) in states.indexed) {
      deck.defineState(StateDescriptor(s, type: const IntType())).set(i + 1);
    }
    return r;
  }

  /// The guest's end of a session of [r], served with [subscription].
  RpcPeerEndpoint serve(Registry r, {int subscription = 4096}) {
    final (g, h) = RpcChannelTransport.pair();
    final host = RpcPeerEndpoint(transport: h);
    r
        .participant(const Principal('widlet', 'b'))
        .serve(host, limits: SessionLimits(subscription: subscription));
    host.start();
    final own = RpcPeerEndpoint(transport: g)..start();
    opened.addAll([host, own]);
    return own;
  }

  test('asked past its bound, a session carries everything, and the '
      'participant says so', () async {
    final r = deckOf(['deck.s1', 'deck.s2', 'deck.s3']);
    final p = await RemoteParticipant.joinEndpoint(serve(r, subscription: 2));
    final errors = <ParticipantError>[];
    p.errors.listen(errors.add);
    expect(await p.fetch('deck.s1'), {null: 1});
    final s2 = p.watch('deck.s2').listen((_) {});
    final s3 = p.watch('deck.s3').listen((_) {});
    expect(await p.fetch('deck.s3'), {null: 3}, reason: 'none left out');
    expect(p.read('deck.s2'), 2);
    expect(errors.single.code, ParticipantErrorCode.overLimit);
    expect(errors.single.op['op'], 'subscribe');
    await s2.cancel();
    await s3.cancel();
    await p.dispose();
  });

  test(
    'a call answered in a run its copy has left waits for nothing',
    () async {
      final r1 = deckOf(['deck.s1']);
      final r2 = deckOf(['deck.s1']);
      final mirror = RegistryMirror();
      Future<void> synced() => mirror.changes.firstWhere((_) => mirror.synced);
      mirror.follow(ParlanceClient(serve(r1)));
      await synced();
      mirror.follow(ParlanceClient(serve(r2)));
      await mirror.changes.firstWhere(
        (_) => mirror.synced && mirror.read('deck.s1') == 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final took = Stopwatch()..start();
      expect(await mirror.reach(r1.epoch, r1.seq + 10), isFalse);
      expect(took.elapsed, lessThan(const Duration(milliseconds: 500)));
      expect(await mirror.reach(r2.epoch, r2.seq), isTrue);
      await mirror.dispose();
    },
  );

  test(
    'after a tick, a command\'s check is asked once for every feed',
    () async {
      final r = deckOf(['deck.s1']);
      var asked = 0;
      final deck = r.participant(
        const Principal('lamp'),
        vocabularies: [WordSet.open('lamp')],
      );
      deck.defineCommand(
        CommandDescriptor('lamp.turn', callers: Callers.only(['widlet'])),
        (_) {},
        whyNot: () {
          asked++;
          return null;
        },
      );
      final light = deck.defineState(
        StateDescriptor('lamp.on', type: const BoolType()),
      );
      final guests = [
        for (final _ in [1, 2, 3])
          await RemoteParticipant.joinEndpoint(serve(r)),
      ];
      for (final g in guests) {
        await g.settle();
      }
      await pumpEventQueue();
      final before = asked;
      light.set(true);
      await pumpEventQueue();
      expect(asked - before, 1, reason: 'three feeds, one answer');
      for (final g in guests) {
        await g.dispose();
      }
    },
  );
}
