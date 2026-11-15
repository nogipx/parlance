import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/local.dart' show Participants;

/// A part whose connection went without its host seeing it (a link half
/// open) comes back before its old session ends: the new session of the
/// same principal takes the old one's place, as an MQTT broker takes a
/// client's session over (SPEC §14). Another principal can publish the same
/// vocabulary independently without taking it over.
const kittens = Principal('plugin', 'kittens');

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late Registry r;
  setUp(() => r = Registry());
  tearDown(() => r.dispose());

  test('a part back before its old session ended takes its place', () async {
    final other = r.participant(
      const Principal('plugin', 'other'),
      vocabularies: [WordSet.open('kittens')],
    );
    final untouched = other.defineState(
      StateDescriptor('kittens.lamp', type: const BoolType()),
    )..set(false);
    final reconnect = Completer<void>();
    addTearDown(() {
      if (!reconnect.isCompleted) reconnect.complete();
    });
    final sessions = <RemoteSession>[];
    final hosts = <RpcPeerEndpoint>[];
    final connection = RpcClientConnection(
      transportFactory: (_) async {
        if (hosts.isNotEmpty) await reconnect.future;
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
      StateDescriptor('plugin/kittens/kittens.lamp', type: const BoolType()),
    );
    lamp.set(false);
    await p.flush();
    expect(r.read('plugin/kittens/kittens.lamp'), false);

    final targets = <List<WordTarget>>[];
    final observing = p
        .targetChanges(vocabulary: WordSet.open('kittens'))
        .listen(targets.add);
    await settle();
    expect(targets.last, hasLength(2));

    // The link goes; the host does not see it, and ends no session.
    final offline = connection.state.firstWhere((s) => s is! RpcClientOnline);
    await hosts.last.close();
    await offline;
    await settle();
    expect(await p.targets(vocabulary: WordSet.open('kittens')), isEmpty);
    expect(targets.last, isEmpty);
    lamp.set(true);
    reconnect.complete();

    final back = DateTime.now().add(const Duration(seconds: 5));
    while (r.read('plugin/kittens/kittens.lamp') != true &&
        DateTime.now().isBefore(back)) {
      await settle();
    }
    expect(sessions, hasLength(2), reason: 'it came back');
    expect(r.read('plugin/other/kittens.lamp'), false);
    expect(
      r.read('plugin/kittens/kittens.lamp'),
      true,
      reason: 'its word, as it stands',
    );

    // The host sees the old link go at last: the new session stays.
    sessions.first.dispose();
    await settle();
    expect(r.read('plugin/kittens/kittens.lamp'), true);

    await settle();
    expect(targets.last, hasLength(2));
    await observing.cancel();
    await p.dispose();
    untouched.set(true);
    expect(r.read('plugin/other/kittens.lamp'), true);
    await connection.dispose();
    for (final s in sessions) {
      s.dispose();
    }
  });

  test("another principal's session is not taken over", () {
    final (_, s) = RpcChannelTransport.memoryPair();
    final original = r.participant(
      kittens,
      vocabularies: [WordSet.open('kittens')],
    );
    final session = original.serve(RpcPeerEndpoint(transport: s));
    final first = original.defineState(
      StateDescriptor('kittens.lamp', type: const BoolType()),
    );
    first.set(true);
    final other = r.participant(
      const Principal('plugin', 'other'),
      vocabularies: [WordSet.open('kittens')],
    );
    final second = other.defineState(
      StateDescriptor('kittens.lamp', type: const BoolType()),
    );
    second.set(false);
    expect(r.read('plugin/kittens/kittens.lamp'), true);
    expect(r.read('plugin/other/kittens.lamp'), false);
    other.dispose();
    expect(r.read('plugin/kittens/kittens.lamp'), true);
    first.set(false);
    expect(r.read('plugin/kittens/kittens.lamp'), false);
    session.dispose();
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
