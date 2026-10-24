import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:switchboard/registry.dart';
import 'package:switchboard/remote.dart';
import 'package:test/test.dart';

import '../registry/fixture.dart';

/// One connection: a session for [principal] on the registry, and a client.
final class Link {
  Link._(this.client, this.session, this._closers);

  static Link open(Registry r, Principal principal, {required bool wire}) {
    final (c, s) = wire
        ? RpcChannelTransport.pair()
        : RpcChannelTransport.memoryPair();
    final session = RegistryResponder(r, principal: principal);
    final responder = RpcResponderEndpoint(transport: s)
      ..registerServiceContract(session)
      ..start();
    final caller = RpcCallerEndpoint(transport: c);
    return Link._(SwitchboardClient(caller), session, [
      caller.close,
      responder.close,
    ]);
  }

  final SwitchboardClient client;
  final RegistryResponder session;
  final List<Future<void> Function()> _closers;

  /// The connection drops: the host ends the session.
  Future<void> close() async {
    session.close();
    for (final c in _closers) {
      await c();
    }
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  for (final wire in [false, true]) {
    group(wire ? 'over frames' : 'in memory', () {
      late Fixture f;
      late Link link;

      setUp(() {
        f = Fixture();
        link = Link.open(f.r, user, wire: wire);
      });
      tearDown(() async {
        await link.close();
        await f.r.dispose();
      });

      test('describe tells the catalog, the epoch and the protocol', () async {
        final d = await link.client.describe();
        expect(d['epoch'], f.r.epoch);
        expect(d['protocol'], switchboardProtocol);
        final names = [
          for (final x in d['descriptors'] as List) (x as Map)['name'],
        ];
        expect(names, contains('studio.show'));
      });

      test('a call answers its result; a refusal is a result too', () async {
        final ok = await link.client.call('studio.show', {'scene': 'main'});
        expect(ok, isA<CallDone<Object?>>());
        expect(f.r.read('studio.program'), 'main');
        final bad = await link.client.call('studio.show', {'scene': 'gone'});
        expect(
          bad,
          isA<CallRefused>().having(
            (r) => r.code,
            'code',
            Refusal.invalidParams,
          ),
        );
      });

      test('the session acts for its principal only', () async {
        final v = Link.open(f.r, viewer, wire: wire);
        addTearDown(v.close);
        final r = await v.client.call('audio.mute', {'on': true});
        expect(
          r,
          isA<CallRefused>().having(
            (x) => x.code,
            'code',
            Refusal.notPermitted,
          ),
        );
      });

      test(
        'a guard denial comes with its guard; the user may override',
        () async {
          f.r.addGuard(
            'no-test',
            (c) => c.params['scene'] == 'test' ? 'no' : null,
          );
          final r = await link.client.call('studio.show', {'scene': 'test'});
          expect(
            r,
            isA<CallRefused>()
                .having((x) => x.guard, 'guard', 'no-test')
                .having((x) => x.overridable, 'overridable', isTrue),
          );
          expect(
            (await link.client.call('studio.show', {
              'scene': 'test',
            }, override: true)).ok,
            isTrue,
          );
        },
      );

      test(
        'a retry with the same id after a reconnect does not run twice',
        () async {
          await link.client.call('studio.show', {'scene': 'main'}, id: 'once');
          await link.close();
          link = Link.open(f.r, user, wire: wire);
          final again = await link.client.call('studio.show', {
            'scene': 'main',
          }, id: 'once');
          expect(again, isA<CallDone<Object?>>());
          expect(f.shown, ['main']);
          final other = Link.open(f.r, agent, wire: wire);
          addTearDown(other.close);
          await other.client.call('studio.show', {
            'scene': 'break',
          }, id: 'once');
          expect(f.shown, ['main', 'break'], reason: 'ids are per principal');
        },
      );

      test('the test mark travels', () async {
        final changes = <StateChange>[];
        f.r.ticks.listen((t) => changes.addAll(t.changes));
        await link.client.call('audio.mute', {'on': true}, test: true);
        await settle();
        expect(changes.single.cause.test, isTrue);
      });

      test(
        'feed: the catalog, a snapshot, then ticks; catalog changes too',
        () async {
          f.muted.set(true);
          final items = <RemoteFeed>[];
          final sub = link.client.feed().listen(items.add);
          await settle();
          f.program.set('break');
          f.r.defineFact(
            FactDescriptor('x.new', type: const AnyType()),
            by: owner,
          );
          await settle();
          expect(items[0], isA<RemoteCatalog>());
          final snap = (items[1] as RemoteSnapshot).snapshot;
          expect(snap.states['audio.muted'], {null: true});
          final tick = items.whereType<RemoteTick>().single.tick;
          expect(tick.changes.single.value, 'break');
          final last = items.whereType<RemoteCatalog>().last.json;
          expect([
            for (final d in last['descriptors'] as List) (d as Map)['name'],
          ], contains('x.new'));
          await sub.cancel();
        },
      );

      test(
        'the mirror resumes after a lost connection without gaps or repeats',
        () async {
          final mirror = RegistryMirror();
          addTearDown(mirror.dispose);
          final seen = <Tick>[];
          mirror.ticks.listen(seen.add);
          mirror.follow(link.client);
          await settle();
          f.muted.set(true);
          await settle();
          expect(mirror.read('audio.muted'), true);

          await link.close();
          await settle();
          expect(mirror.synced, isFalse);
          f.program.set('main');
          f.gain.set(-6, key: 'mic');
          f.muted.set(false);

          link = Link.open(f.r, user, wire: wire);
          mirror.follow(link.client);
          await settle();
          expect(mirror.synced, isTrue);
          expect(mirror.read('studio.program'), 'main');
          expect(mirror.read('audio.gain', key: 'mic'), -6);
          expect(mirror.read('audio.muted'), false);
          expect(mirror.seq, f.r.seq);
          for (var i = 1; i < seen.length; i++) {
            expect(
              seen[i].from,
              seen[i - 1].to + 1,
              reason: 'no gap, no repeat',
            );
          }
        },
      );

      test('a layer holds while the session lasts', () async {
        f.muted.set(false);
        final events = <LayerEvent>[];
        // The stream ends with CANCELLED when the connection drops.
        final sub = link.client.layerEvents().listen(
          events.add,
          onError: (Object _) {},
        );
        await settle();
        final id = await link.client.pushLayer('audio.muted', value: true);
        await settle();
        expect(f.r.read('audio.muted'), true);
        await link.client.popLayer(id);
        await settle();
        expect(f.r.read('audio.muted'), false);

        await link.client.pushLayer('audio.muted', value: true);
        await settle();
        await link.close();
        await settle();
        expect(f.r.read('audio.muted'), false, reason: 'gone with the session');
        expect(events.map((e) => e.outcome), contains(LayerOutcome.removed));
        await sub.cancel();
        link = Link.open(f.r, user, wire: wire);
      });

      test(
        'a lost answer is CallLost with the id; the retry runs once',
        () async {
          final runs = <String>[];
          f.r.defineCommand(
            CommandDescriptor('x.go', callers: Callers.only(['user'])),
            (c) => runs.add(c.id),
          );
          final first = await link.client.call('x.go', {}, id: 'k');
          expect(first, isA<CallDone<Object?>>());
          await link.close();
          final lost = await link.client.call('x.go', {}, id: 'k2');
          expect(lost, isA<CallLost>());
          expect((lost as CallLost).id, 'k2');
          final again = Link.open(f.r, user, wire: wire);
          addTearDown(again.close);
          expect(await again.client.call('x.go', {}, id: 'k'), isA<CallDone<Object?>>());
          expect(runs, ['user:local/k'], reason: 'the retry did not run again');
        },
      );

      test(
        'recent facts come from the registry, older than the session',
        () async {
          final raid = f.r.defineFact(
            FactDescriptor('x.raid', type: const IntType()),
            by: owner,
          );
          raid.emit(1);
          raid.emit(2);
          final late = Link.open(f.r, user, wire: wire);
          addTearDown(late.close);
          expect(
            [for (final m in await late.client.recent('x.raid', 5)) m.payload],
            [1, 2],
          );
        },
      );

      test(
        'a call answers the seq a mirror reaches to show its writes',
        () async {
          final mirror = RegistryMirror()..follow(link.client);
          addTearDown(mirror.dispose);
          await settle();
          final r = await link.client.callAt('studio.show', {'scene': 'break'});
          expect(r.seq, f.r.seq);
          expect(await mirror.reach(r.epoch!, r.seq!), isTrue);
          expect(mirror.read('studio.program'), 'break');
          expect(
            await mirror.reach(
              r.epoch!,
              r.seq! + 5,
              timeout: const Duration(milliseconds: 30),
            ),
            isFalse,
          );
        },
      );

      test('layer errors carry rpc statuses', () async {
        Future<RpcStatus?> status(Future<Object?> f) async {
          try {
            await f;
            return null;
          } on RpcStatusException catch (e) {
            return e.statusCode;
          }
        }

        expect(
          await status(link.client.pushLayer('nope', value: 1)),
          RpcStatus.notFound,
        );
        expect(
          await status(link.client.pushLayer('audio.muted', value: 'yes')),
          RpcStatus.invalidArgument,
        );
        expect(await status(link.client.popLayer('nope')), RpcStatus.notFound);
        final v = Link.open(f.r, viewer, wire: wire);
        addTearDown(v.close);
        expect(
          await status(v.client.pushLayer('audio.muted', value: true)),
          RpcStatus.permissionDenied,
        );
      });
    });
  }
}
