import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:switchboard/registry.dart';
import 'package:switchboard/remote.dart';
import 'package:test/test.dart';

import '../registry/fixture.dart';

/// One connection: a session for [principal] on the registry, and a client.
final class Link {
  Link._(this.client, this.session, this.endpoint, this._closers);

  static Link open(
    Registry r,
    Principal principal, {
    required bool wire,
    SessionRights rights = SessionRights.none,
  }) {
    final (c, s) = wire
        ? RpcChannelTransport.pair()
        : RpcChannelTransport.memoryPair();
    final responder = RpcPeerEndpoint(transport: s);
    final session = RegistryResponder(
      responder,
      r,
      principal: principal,
      rights: rights,
    );
    responder
      ..registerServiceContract(session)
      ..start();
    final caller = RpcPeerEndpoint(transport: c)..start();
    return Link._(SwitchboardClient(caller), session, caller, [
      caller.close,
      responder.close,
    ]);
  }

  final SwitchboardClient client;
  final RegistryResponder session;

  /// The participant's side of the connection.
  final RpcPeerEndpoint endpoint;
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

      test(
        'a mirror back with nothing new since follows again at once',
        () async {
          final mirror = RegistryMirror();
          addTearDown(mirror.dispose);
          mirror.follow(link.client);
          await settle();
          expect(mirror.synced, isTrue);
          await link.close();
          await settle();
          expect(mirror.synced, isFalse);

          link = Link.open(f.r, user, wire: wire);
          mirror.follow(link.client);
          await settle();
          expect(mirror.synced, isTrue, reason: 'no tick to wait for');
        },
      );

      group('a subscription', () {
        late RawFactEmitter raid;
        late RawFactEmitter cheer;
        late RegistryMirror mirror;
        final seen = <Tick>[];

        setUp(() {
          raid = f.r.defineFact(
            FactDescriptor('x.raid', type: const IntType()),
            by: owner,
          );
          cheer = f.r.defineFact(
            FactDescriptor('x.cheer', type: const IntType()),
            by: owner,
          );
          seen.clear();
          mirror = RegistryMirror()..ticks.listen(seen.add);
        });
        tearDown(() => mirror.dispose());

        void noGaps() {
          for (var i = 1; i < seen.length; i++) {
            expect(
              seen[i].from,
              seen[i - 1].to + 1,
              reason: 'no gap, no repeat',
            );
          }
        }

        test('the feed carries only the states and facts it names, and the '
            'ticks it leaves out leave no gap', () async {
          await mirror.subscribe(states: {'audio.muted'}, facts: {'x.raid'});
          mirror.follow(link.client);
          await settle();
          // Each in a tick of its own.
          for (final write in <void Function()>[
            () => f.program.set('main'),
            () => f.muted.set(true),
            () => raid.emit(1),
            () => cheer.emit(2),
            () => f.gain.set(-6, key: 'mic'),
            () => f.muted.set(false),
            () => f.program.set('break'),
          ]) {
            write();
            await Future<void>.delayed(Duration.zero);
          }
          await settle();
          expect(mirror.read('audio.muted'), false);
          expect(mirror.read('studio.program'), isNull);
          expect(mirror.readAll('audio.gain'), isEmpty);
          expect(
            {for (final t in seen) ...t.changes.map((c) => c.state)},
            {'audio.muted'},
          );
          expect([for (final t in seen) ...t.facts.map((x) => x.payload)], [1]);
          expect(seen.length, 3);
          noGaps();
          expect(
            mirror.seq,
            lessThan(f.r.seq),
            reason: 'the last tick had nothing it follows',
          );
        });

        test('a state it takes in comes with its values at once; one it '
            'leaves goes from the copy', () async {
          f.program.set('main');
          f.muted.set(true);
          await mirror.subscribe(states: {'audio.muted'});
          mirror.follow(link.client);
          await settle();
          expect(mirror.read('studio.program'), isNull);
          await mirror.subscribe(states: {'audio.muted', 'studio.program'});
          expect(mirror.read('studio.program'), 'main');
          await mirror.subscribe(states: {'studio.program'});
          expect(mirror.read('audio.muted'), isNull);
          f.program.set('break');
          f.muted.set(false);
          await settle();
          expect(mirror.read('studio.program'), 'break');
          expect(mirror.read('audio.muted'), isNull);
          await mirror.subscribe();
          expect(mirror.read('audio.muted'), false);
          noGaps();
        });

        test('a new connection subscribes again before its feed', () async {
          await mirror.subscribe(states: {'audio.muted'}, facts: const {});
          mirror.follow(link.client);
          await settle();
          await link.close();
          await settle();
          f.muted.set(true);
          f.program.set('main');
          link = Link.open(f.r, user, wire: wire);
          mirror.follow(link.client);
          await settle();
          expect(mirror.read('audio.muted'), true);
          expect(mirror.read('studio.program'), isNull);
          expect(link.session.states, {'audio.muted'});
          expect(link.session.facts, isEmpty);
          raid.emit(1);
          await settle();
          expect(seen.expand((t) => t.facts), isEmpty);
          noGaps();
        });

        test('the host knows what the session hears: the facts its feeds '
            'carry, and those it read the recent of', () async {
          bool raids(String fact) => fact == 'x.raid';
          expect(link.session.hears(raids), isTrue, reason: 'all, at first');
          await link.client.subscribe(states: const [], facts: ['x.cheer']);
          expect(link.session.hears(raids), isFalse);
          expect(link.session.hears((x) => x.startsWith('x.')), isTrue);
          await link.client.recent('x.raid', 1);
          expect(link.session.hears(raids), isTrue);
        });
      });

      group('a state with readers', () {
        late RawStateWriter secret;
        const plugin = Principal('plugin', 'kittens');

        setUp(() {
          secret = f.r.defineState(
            StateDescriptor(
              'kittens.settings',
              type: const MapType(AnyType()),
              readers: const Callers({
                'plugin:kittens': Access.allow,
                'plugin': Access.deny,
                '*': Access.allow,
              }),
            ),
            by: owner,
          )..set({'channel': 'kittens'});
          // A setter, for a layer to hold it.
          f.r.defineCommand(
            CommandDescriptor(
              'kittens.settings.set',
              params: const ObjectType({'value': Field(MapType(AnyType()))}),
              callers: Callers.only(['user']),
              sets: const Sets('kittens.settings'),
            ),
            (c) => secret.set(c.params['value']),
          );
        });

        Future<RpcStatus?> status(Future<Object?> f) async {
          try {
            await f;
            return null;
          } on RpcStatusException catch (e) {
            return e.statusCode;
          }
        }

        test('a session it does not name sees no value of it: not in a '
            'snapshot, a tick, a subscription, why or the layers', () async {
          final other = Link.open(
            f.r,
            const Principal('plugin', 'daycare'),
            wire: wire,
          );
          addTearDown(other.close);
          final mirror = RegistryMirror()..follow(other.client);
          addTearDown(mirror.dispose);
          final ticks = <Tick>[];
          mirror.ticks.listen(ticks.add);
          await settle();
          expect(mirror.readAll('kittens.settings'), isEmpty);
          f.muted.set(true);
          await settle();
          secret.set({'channel': 'puppies'});
          await settle();
          f.muted.set(false);
          await settle();
          expect(mirror.readAll('kittens.settings'), isEmpty);
          expect(ticks.expand((t) => t.changes).map((c) => c.state).toSet(), {
            'audio.muted',
          });
          for (var i = 1; i < ticks.length; i++) {
            expect(ticks[i].from, ticks[i - 1].to + 1);
          }
          expect(
            await status(other.client.subscribe(states: ['kittens.settings'])),
            RpcStatus.permissionDenied,
          );
          expect(
            await status(other.client.why('kittens.settings')),
            RpcStatus.permissionDenied,
          );
          f.r.pushLayer(
            'kittens.settings',
            value: {'channel': 'held'},
            owner: 'test',
            by: user,
          );
          expect(
            (await other.client.layers()).map((l) => l.state),
            isNot(contains('kittens.settings')),
          );
          expect((await other.client.describe())['unreadable'], [
            'kittens.settings',
          ]);
        });

        test('a fact with readers: a session it does not name hears it not, '
            'nor its recent, nor follows from it', () async {
          final whisper = f.r.defineFact(
            FactDescriptor(
              'kittens.whisper',
              type: const TextType(),
              readers: const Callers({
                'plugin:kittens': Access.allow,
                'plugin': Access.deny,
                '*': Access.allow,
              }),
            ),
            by: owner,
          );
          final other = Link.open(
            f.r,
            const Principal('plugin', 'daycare'),
            wire: wire,
          );
          final own = Link.open(f.r, plugin, wire: wire);
          addTearDown(other.close);
          addTearDown(own.close);
          final heard = <String, List<Object?>>{'other': [], 'own': []};
          for (final (who, l) in [('other', other), ('own', own)]) {
            final sub = l.client.feed().listen((i) {
              if (i case RemoteTick(:final tick)) {
                heard[who]!.addAll(tick.facts.map((m) => m.payload));
              }
            });
            addTearDown(sub.cancel);
          }
          await settle();
          whisper.emit('psst', id: 'w1');
          await settle();
          expect(heard, {
            'other': <Object?>[],
            'own': ['psst'],
          });
          expect(
            await status(other.client.recent('kittens.whisper', 5)),
            RpcStatus.permissionDenied,
          );
          expect(
            await status(other.client.subscribe(facts: ['kittens.whisper'])),
            RpcStatus.permissionDenied,
          );
          expect(other.session.hears((x) => x == 'kittens.whisper'), isFalse);
          expect(own.session.hears((x) => x == 'kittens.whisper'), isTrue);
          expect(
            [
              for (final m in await own.client.recent('kittens.whisper', 5))
                m.payload,
            ],
            ['psst'],
          );
        });

        test('the session it names reads it, and so does the crew', () async {
          final own = Link.open(f.r, plugin, wire: wire);
          addTearDown(own.close);
          final mirror = RegistryMirror();
          addTearDown(mirror.dispose);
          await mirror.subscribe(states: {'kittens.settings'});
          mirror.follow(own.client);
          await settle();
          expect(mirror.read('kittens.settings'), {'channel': 'kittens'});
          final crew = RegistryMirror()..follow(link.client);
          addTearDown(crew.dispose);
          await settle();
          expect(crew.read('kittens.settings'), {'channel': 'kittens'});
        });
      });

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
          expect(
            await again.client.call('x.go', {}, id: 'k'),
            isA<CallDone<Object?>>(),
          );
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

      group('a session that owns words', () {
        const plugin = Principal('plugin', 'kittens');
        // The host's rights: words under its id, open facts it produces,
        // a viewer it speaks for.
        final rights = SessionRights(
          define: (p, d) =>
              d.name.startsWith('${p.id}.') ? null : 'only ${p.id}.*',
          produce: (p, fact) => fact == 'platform.follow' ? null : 'not $fact',
          speakFor: (p, by, fact) => by.kind == 'viewer' ? null : 'not $by',
        );
        late Link k;
        late RemoteOwner o;

        setUp(() {
          k = Link.open(f.r, plugin, wire: wire, rights: rights);
          o = RemoteOwner(k.endpoint, k.client);
          k.endpoint.registerServiceContract(o);
        });
        tearDown(() => k.close());

        Future<RpcStatus?> status(Future<Object?> f) async {
          try {
            await f;
            return null;
          } on RpcStatusException catch (e) {
            return e.statusCode;
          }
        }

        Future<void> lamps() async {
          await k.client.define(
            StateDescriptor('kittens.lights', type: const BoolType()),
          );
          await o.defineCommand(
            CommandDescriptor(
              'kittens.lights.set',
              params: const ObjectType({'on': Field(BoolType())}),
              callers: Callers.only(['user', 'plugin']),
              sets: const Sets('kittens.lights', value: 'on'),
            ),
            (c) async {
              await k.client.write(
                'kittens.lights',
                value: c.params['on'],
                parent: c.id,
              );
              return null;
            },
          );
        }

        test('its words are the registry\'s: others call its command, '
            'it serves it, and what it writes follows from the call', () async {
          await lamps();
          expect(f.r.setterOf('kittens.lights'), 'kittens.lights.set');
          final r = await f.r.call('kittens.lights.set', {
            'on': true,
          }, by: user);
          expect(r, isA<CallDone<Object?>>());
          expect(f.r.read('kittens.lights'), true);
          final change = f.r.lastChange('kittens.lights')!;
          expect(change.cause.by, plugin);
          expect(change.cause.parent, isNotNull);
          expect(
            f.r.callRecord(change.cause.parent!)?.command,
            'kittens.lights.set',
          );
        });

        test('a handler that throws fails the call with its words', () async {
          await o.defineCommand(
            CommandDescriptor('kittens.feed', callers: Callers.only(['user'])),
            (c) => throw StateError('no fish'),
          );
          final r = await f.r.call('kittens.feed', {}, by: user);
          expect(r.whyNot, contains('no fish'));
        });

        test('it defines only what the host lets it, writes only its own, '
            'of their types', () async {
          await lamps();
          expect(
            await status(
              k.client.define(
                StateDescriptor('studio.lights', type: const BoolType()),
              ),
            ),
            RpcStatus.permissionDenied,
          );
          expect(
            await status(
              k.client.define(
                StateDescriptor('kittens.lights', type: const BoolType()),
              ),
            ),
            RpcStatus.alreadyExists,
          );
          expect(
            await status(k.client.write('audio.muted', value: true)),
            RpcStatus.permissionDenied,
          );
          expect(
            await status(k.client.write('kittens.lights', value: 'yes')),
            RpcStatus.invalidArgument,
          );
          final caller = Link.open(f.r, agent, wire: wire);
          addTearDown(caller.close);
          expect(
            await status(
              caller.client.define(
                StateDescriptor('agent.x', type: const BoolType()),
              ),
            ),
            RpcStatus.permissionDenied,
          );
        });

        test("it says its facts, an open one it produces, for a viewer the "
            "host lets it speak for; a repeat of an id is dropped", () async {
          f.r.defineFact(
            FactDescriptor(
              'platform.follow',
              type: const AnyType(),
              open: true,
            ),
            by: owner,
          );
          f.r.defineFact(
            FactDescriptor('platform.raid', type: const AnyType(), open: true),
            by: owner,
          );
          await k.client.define(
            FactDescriptor('kittens.adopted', type: const AnyType()),
          );
          expect(await k.client.emit('kittens.adopted', {'name': 'Tom'}), true);
          expect(
            await k.client.emit(
              'platform.follow',
              {'viewer': 'Bo'},
              id: 'f1',
              by: viewer,
            ),
            true,
          );
          expect(
            await k.client.emit('platform.follow', {}, id: 'f1', by: viewer),
            false,
          );
          expect(f.r.recent('platform.follow').single.cause.by, viewer);
          expect(
            await status(k.client.emit('platform.raid', {})),
            RpcStatus.permissionDenied,
          );
          expect(
            await status(k.client.emit('platform.follow', {}, by: user)),
            RpcStatus.permissionDenied,
          );
          expect(
            await status(k.client.emit('audio.nothing', {})),
            RpcStatus.notFound,
          );
        });

        test('what it does in answer to a fact follows from it', () async {
          await k.client.define(
            FactDescriptor('kittens.adopted', type: const AnyType()),
          );
          await k.client.emit('kittens.adopted', {});
          final fact = f.r.recent('kittens.adopted').single;
          await lamps();
          await k.client.call('kittens.lights.set', {
            'on': true,
          }, parent: fact.id);
          final r = f.r.callRecord(
            f.r.lastChange('kittens.lights')!.cause.parent!,
          );
          expect(r?.cause.parent, fact.id);
        });

        test('its words go with the session', () async {
          await lamps();
          await k.close();
          expect(f.r.stateDescriptor('kittens.lights'), isNull);
          final r = await f.r.call('kittens.lights.set', {
            'on': true,
          }, by: user);
          expect(r, isA<CallRefused>());
        });
      });
    });
  }
}
