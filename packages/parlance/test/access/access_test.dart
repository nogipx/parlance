import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/testing.dart';
import 'package:parlance/tools.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:parlance/src/remote/contract.dart'
    show WireFeedRequest, WireFeedItem;
import 'package:test/test.dart';

import '../addressing/provider_test.dart' as f;

const denied = Callers({});
const warning = Callers({'*': Access.warn});
WordAddress at(String word) => WordAddress(f.work, 'counter.$word');
Matcher refused = isA<CallRefused>().having(
  (r) => r.code,
  'code',
  Refusal.notPermitted,
);
Matcher revoked = isA<StreamFailure>().having(
  (e) => e.code,
  'code',
  StreamFailureCode.notPermitted,
);

void main() {
  for (final ownerRemote in [false, true]) {
    for (final readerRemote in [false, true]) {
      group('owner=$ownerRemote reader=$readerRemote', () {
        late TestHost host;
        late IParticipant reader;
        late f.ICounterClient client;
        late f.Counting counter;
        setUp(() async {
          host = TestHost();
          counter = f.Counting(2);
          if (ownerRemote) {
            final p = await host.join(
              f.work,
              vocabularies: [f.counterWords],
              access: const WordAccess(callers: Callers.anyone),
            );
            await p.attach([counter]);
          } else {
            host.participant(
              f.work,
              owners: [counter],
              access: const WordAccess(callers: Callers.anyone),
            );
          }
          reader = readerRemote
              ? await host.join(f.ann)
              : host.participant(f.ann);
          client = f.ICounterClient(participant: reader, provider: f.work);
          await host.settle();
        });
        tearDown(() async {
          await host.dispose();
        });

        test(
          'host overrides and clearing affect calls, catalogs and discovery',
          () async {
            host.setAccess(
              address: at('add'),
              access: const WordAccess(callers: denied),
            );
            await host.settle();
            expect(
              client.status(f.CounterCommand.add),
              const WordNotPermitted(),
            );
            expect(
              await reader.raw.call(at('add').toString(), {'amount': 4}),
              refused,
            );
            expect(
              (await reader.providers(
                word: f.CounterCommand.add,
              )).single.words.single.status,
              const WordNotPermitted(),
            );
            expect(client.mismatches, isEmpty);
            host.clearAccess(address: at('add'));
            await host.settle();
            expect(await client.add(amount: 4), 6);
            expect(client.status(f.CounterCommand.add), const WordReady());
          },
        );

        test(
          'state and fact listeners revoke, clear cached values and resume',
          () async {
            final values = <int?>[], facts = <int>[];
            final s = client.value.changes.listen(values.add);
            final t = client.changed.payloads.listen((e) => facts.add(e.value));
            await host.settle();
            expect(client.value.value, 2);
            host.setAccess(
              address: at('value'),
              access: const WordAccess(readers: denied),
            );
            host.setAccess(
              address: at('changed'),
              access: const WordAccess(readers: denied),
            );
            await host.settle();
            counter.value.set(20);
            counter.announce('hidden', 20);
            await host.settle();
            expect(client.value.value, isNull);
            expect(values.last, isNull);
            expect(facts, isEmpty);
            host.clearAccess(address: at('value'));
            host.clearAccess(address: at('changed'));
            await host.settle();
            expect(client.value.value, 20);
            expect(values.last, 20);
            expect(facts, isEmpty, reason: 'revoked facts are not replayed');
            counter.announce('visible', 21);
            await host.settle();
            expect(facts, [21]);
            await s.cancel();
            await t.cancel();
          },
        );

        test(
          'paused consumers do not replay revoked values or facts after regrant',
          () async {
            final values = <int?>[], facts = <int>[];
            final states = client.value.changes.listen(values.add);
            final events = client.changed.payloads.listen(
              (e) => facts.add(e.value),
            );
            await host.settle();
            states.pause();
            events.pause();
            counter.value.set(77);
            counter.announce('queued', 77);
            await host.settle();
            host.setAccess(
              address: at('value'),
              access: const WordAccess(readers: denied),
            );
            host.setAccess(
              address: at('changed'),
              access: const WordAccess(readers: denied),
            );
            await host.settle();
            counter.value.set(99);
            counter.announce('revoked', 99);
            await host.settle();
            host.clearAccess(address: at('value'));
            host.clearAccess(address: at('changed'));
            await host.settle();
            states.resume();
            events.resume();
            await host.settle();
            expect(values, isNot(contains(77)));
            expect(values.last, 99);
            expect(facts, isEmpty);
            counter.announce('new', 100);
            await host.settle();
            expect(facts, [100]);
            await states.cancel();
            await events.cancel();
          },
        );

        test(
          'rapid revoke and regrant discard already queued snapshots and facts',
          () async {
            final values = <int?>[], facts = <int>[];
            final s = client.value.changes.listen(values.add);
            final t = client.changed.payloads.listen((e) => facts.add(e.value));
            await host.settle();
            s.pause();
            t.pause();
            counter.value.set(77);
            counter.announce('old', 77);
            await host.settle();
            counter.value.set(99);
            counter.announce('also-old', 99);
            await host.settle();
            host.setAccess(
              address: at('value'),
              access: const WordAccess(readers: denied),
            );
            host.setAccess(
              address: at('changed'),
              access: const WordAccess(readers: denied),
            );
            host.clearAccess(address: at('value'));
            host.clearAccess(address: at('changed'));
            await host.settle();
            s.resume();
            t.resume();
            await host.settle();
            // A remote mirror may notify its cleared cache before the fresh snapshot.
            expect(values.first, 2);
            expect(values, isNot(contains(77)));
            expect(values.last, 99);
            expect(facts, isEmpty);
            await s.cancel();
            await t.cancel();
          },
        );

        test(
          'state and fact warnings describe admission rather than each update',
          () async {
            host.setAccess(
              address: at('value'),
              access: const WordAccess(readers: warning),
            );
            host.setAccess(
              address: at('item'),
              access: const WordAccess(readers: warning),
            );
            host.setAccess(
              address: at('changed'),
              access: const WordAccess(readers: warning),
            );
            await host.settle();
            final seen = <AccessWarning>[];
            final observer = host.registry.accessWarnings.listen(seen.add);
            final s = client.value.changes.listen((_) {});
            final k = client.item.changes.listen((_) {});
            final t = client.changed.payloads.listen((_) {});
            await host.settle();
            expect(seen, isNotEmpty);
            seen.clear();
            counter.value.set(5);
            counter.item.set('same-id', 5);
            counter.announce('fresh', 5);
            await host.settle();
            expect(
              seen,
              isEmpty,
              reason: 'updates are not additional admissions',
            );
            await client.changed.recent(10);
            await host.settle();
            expect(seen.single.operation, AccessOperation.read);
            await s.cancel();
            await k.cancel();
            await t.cancel();
            await observer.cancel();
          },
        );

        test(
          'retry checks current ACL without losing completed identity',
          () async {
            final raw = reader.raw;
            expect(
              (await raw.call(at('add').toString(), {
                'amount': 1,
              }, id: 'retry')).ok,
              isTrue,
            );
            host.setAccess(
              address: at('add'),
              access: const WordAccess(callers: denied),
            );
            await host.settle();
            expect(
              await raw.call(at('add').toString(), {'amount': 1}, id: 'retry'),
              refused,
            );
            host.clearAccess(address: at('add'));
            await host.settle();
            expect(
              (await raw.call(at('add').toString(), {
                'amount': 1,
              }, id: 'retry')).ok,
              isTrue,
            );
            expect(await client.current(), 3);
          },
        );

        test(
          'warn observes real interactions while inspection stays silent',
          () async {
            final seen = <AccessWarning>[];
            final sub = host.registry.accessWarnings.listen(seen.add);
            host.setAccess(
              address: at('add'),
              access: const WordAccess(callers: warning),
            );
            host.setAccess(
              address: at('current'),
              access: const WordAccess(callers: warning),
            );
            host.setAccess(
              address: at('samples'),
              access: const WordAccess(readers: warning),
            );
            await host.settle();
            client.status(f.CounterCommand.add);
            await reader.providers(vocabulary: f.counterWords);
            await reader.raw.describe();
            await host.settle();
            expect(seen, isEmpty);
            await client.add(amount: 3);
            await client.current();
            expect(await client.samples().toList(), [2, 3]);
            await host.settle();
            expect(seen.map((e) => e.operation), [
              AccessOperation.call,
              AccessOperation.query,
              AccessOperation.openStream,
            ]);
            expect(
              seen.every(
                (e) => e.by == f.ann && e.word.startsWith('module/work/'),
              ),
              isTrue,
            );
            expect(seen.every((e) => e.id != null), isTrue);
            await sub.cancel();
          },
        );
      });
    }
  }

  test(
    'pre-publication overrides are immutable, isolate providers, survive republishing and respect aliases',
    () async {
      final host = Host();
      addTearDown(host.dispose);
      final rules = {'*': Access.deny};
      host.setAccess(
        address: at('value'),
        access: WordAccess(readers: Callers(rules)),
      );
      rules['*'] = Access.allow;
      var owner = host.participant(
        f.work,
        owners: [f.Counting(2)],
        access: const WordAccess(callers: Callers.anyone),
      );
      host.participant(
        f.personal,
        owners: [f.Counting(8)],
        access: const WordAccess(callers: Callers.anyone),
      );
      final user = host.participant(f.ann);
      final a = f.ICounterClient(participant: user, provider: f.work);
      final b = f.ICounterClient(participant: user, provider: f.personal);
      expect(a.value.value, isNull);
      expect(b.value.value, 8);
      host.alias('module/work/counter.old', at('value').toString());
      expect(user.raw.read('module/work/counter.old'), isNull);
      owner.dispose();
      owner = host.participant(
        f.work,
        owners: [f.Counting(5)],
        access: const WordAccess(callers: Callers.anyone),
      );
      expect(a.value.value, isNull);
      host.clearAccess(address: at('value'));
      expect(a.value.value, 5);
      expect(user.raw.read('module/work/counter.old'), 5);
      expect(
        () => host.setAccess(
          address: at('value'),
          access: const WordAccess(callers: denied),
        ),
        throwsArgumentError,
      );
      expect(
        a.value.value,
        5,
        reason: 'invalid policy leaves current access intact',
      );
      owner.dispose();
    },
  );

  test(
    'host can widen an explicit declaration and clearing restores it',
    () async {
      final host = Host();
      addTearDown(host.dispose);
      final p = host.participant(
        f.work,
        vocabularies: [const WordSet.open('counter')],
        access: const WordAccess(readers: Callers.anyone),
      );
      p.raw
          .defineState(
            StateDescriptor(
              'counter.value',
              type: const IntType(),
              readers: denied,
            ),
          )
          .set(4);
      final user = host.participant(f.ann);
      final client = f.ICounterClient(participant: user, provider: f.work);
      expect(client.value.value, isNull);
      host.setAccess(
        address: at('value'),
        access: const WordAccess(readers: Callers.anyone),
      );
      expect(client.value.value, 4);
      host.clearAccess(address: at('value'));
      expect(client.value.value, isNull);
    },
  );

  test(
    'an asked guard cannot start a handler after revocation; an already started call finishes',
    () async {
      final host = Host();
      addTearDown(host.dispose);
      final p =
          host
                  .participant(
                    f.work,
                    vocabularies: [const WordSet.open('counter')],
                  )
                  .raw
              as LocalParticipant;
      final gate = Completer<void>(), judging = Completer<void>();
      final guard = p.addAskedGuard('wait', (_) async {
        judging.complete();
        await gate.future;
        return null;
      });
      var ran = 0;
      p.defineCommand(
        CommandDescriptor(
          'counter.add',
          params: const RecordType({}),
          callers: Callers.anyone,
        ),
        (_) {
          ran++;
        },
      );
      final user = host.participant(f.ann).raw;
      final first = user.call(at('add').toString(), {});
      await judging.future;
      host.setAccess(
        address: at('add'),
        access: const WordAccess(callers: denied),
      );
      gate.complete();
      expect(await first, refused);
      expect(ran, 0);
      guard.dispose();
      host.clearAccess(address: at('add'));
    },
  );

  for (final ownerRemote in [false, true]) {
    for (final remote in [false, true]) {
      test(
        'active server/client/bidi streams close when access is revoked (owner=$ownerRemote reader=$remote)',
        () async {
          final host = TestHost();
          addTearDown(host.dispose);
          final p = ownerRemote
              ? await host.join(
                  f.work,
                  vocabularies: [f.counterWords],
                  access: const WordAccess(callers: Callers.anyone),
                )
              : host.participant(
                  f.work,
                  vocabularies: [f.counterWords],
                  access: const WordAccess(callers: Callers.anyone),
                );
          final words = GeneratedWords.own(p);
          final output = StreamController<int>();
          addTearDown(output.close);
          words
              .serverStream(f.CounterServerStream.samples)
              .serve((_) => output.stream);
          words
              .clientStream(f.CounterClientStream.sum)
              .serve((_, input) => input.fold(0, (a, b) => a + b));
          words
              .bidiStream(f.CounterBidiStream.scale)
              .serve((_, input) => input);
          await host.settle();
          final reader = remote
              ? await host.join(f.ann)
              : host.participant(f.ann);
          final c = f.ICounterClient(participant: reader, provider: f.work);
          final sampleErrors = <Object>[];
          final samples = c.samples().listen((_) {}, onError: sampleErrors.add);
          final incoming = StreamController<int>();
          addTearDown(incoming.close);
          final result = c.sum(incoming.stream);
          final resultCheck = expectLater(result, throwsA(revoked));
          final bidiInput = StreamController<int>();
          addTearDown(bidiInput.close);
          final bidiErrors = <Object>[];
          final bidi = c
              .scale(bidiInput.stream)
              .listen((_) {}, onError: bidiErrors.add);
          await host.settle();
          host.setAccess(
            address: at('samples'),
            access: const WordAccess(readers: denied),
          );
          host.setAccess(
            address: at('sum'),
            access: const WordAccess(callers: denied),
          );
          host.setAccess(
            address: at('scale'),
            access: const WordAccess(callers: denied),
          );
          await host.settle();
          await resultCheck;
          expect(sampleErrors.single, revoked);
          expect(bidiErrors.single, revoked);
          await samples.cancel();
          await bidi.cancel();
          expect(host.registry.activeStreams, isEmpty);
        },
      );
    }
  }
  test(
    'host policy survives a consumer reconnect and restores the current state',
    () async {
      final host = Host();
      addTearDown(host.dispose);
      host.participant(
        f.work,
        owners: [f.Counting(2)],
        access: const WordAccess(callers: Callers.anyone),
      );
      final endpoints = <RpcPeerEndpoint>[];
      final reconnect = Completer<void>();
      final connection = RpcClientConnection(
        transportFactory: (_) async {
          if (endpoints.isNotEmpty) await reconnect.future;
          final (client, server) = RpcChannelTransport.pair();
          final endpoint = RpcPeerEndpoint(transport: server);
          host.serve(f.ann, endpoint);
          endpoint.start();
          endpoints.add(endpoint);
          return client;
        },
        backoff: const RpcFixedBackoff(Duration(milliseconds: 10)),
      );
      addTearDown(() async {
        if (!reconnect.isCompleted) reconnect.complete();
        await connection.dispose();
        for (final e in endpoints) {
          await e.close();
        }
      });
      final p = await Host.join(connection);
      addTearDown(p.dispose);
      final c = f.ICounterClient(participant: p, provider: f.work);
      await p.settle();
      expect(c.value.value, 2);
      final offline = connection.state.firstWhere((s) => s is! RpcClientOnline);
      await endpoints.first.close();
      await offline;
      host.setAccess(
        address: at('value'),
        access: const WordAccess(readers: denied),
      );
      reconnect.complete();
      for (var i = 0; i < 200 && (endpoints.length < 2 || !p.raw.synced); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await p.settle();
      expect(c.status(f.CounterState.value), const WordNotPermitted());
      expect(c.value.value, isNull);
      host.clearAccess(address: at('value'));
      for (var i = 0; i < 20 && c.value.value == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(c.value.value, 2);
    },
  );
  test(
    'a paused host feed drops revoked payloads even after permission returns',
    () async {
      final host = Host();
      addTearDown(host.dispose);
      final counter = f.Counting(2);
      host.participant(
        f.work,
        owners: [counter],
        access: const WordAccess(callers: Callers.anyone),
      );
      final (_, transport) = RpcChannelTransport.memoryPair();
      final endpoint = RpcPeerEndpoint(transport: transport);
      addTearDown(endpoint.close);
      final session = host.serve(f.ann, endpoint) as RemoteSession;
      final received = <WireFeedItem>[];
      final sub = session.onFeed(const WireFeedRequest()).listen(received.add);
      await pumpEventQueue();
      received.clear();
      sub.pause();
      counter.value.set(77);
      counter.announce('queued', 77);
      await pumpEventQueue();
      host.setAccess(
        address: at('value'),
        access: const WordAccess(readers: denied),
      );
      host.setAccess(
        address: at('changed'),
        access: const WordAccess(readers: denied),
      );
      counter.value.set(99);
      counter.announce('hidden', 99);
      await pumpEventQueue();
      host.clearAccess(address: at('value'));
      host.clearAccess(address: at('changed'));
      await pumpEventQueue();
      sub.resume();
      await pumpEventQueue();
      List<Object?> facts() => [
        for (final i in received.where((i) => i.kind == 'tick'))
          for (final f in i.json['facts'] as List? ?? const [])
            (f as Map)['payload'],
      ];
      expect(facts(), isEmpty);
      expect([
        for (final i in received.where((i) => i.kind == 'tick'))
          for (final c in i.json['changes'] as List? ?? const [])
            (c as Map)['value'],
      ], isNot(contains(77)));
      counter.announce('new', 100);
      await pumpEventQueue();
      expect(facts(), [
        {'value': 100},
      ]);
      await sub.cancel();
      session.dispose();
    },
  );

  test(
    'warn is a structured log event and identifies nested owner calls',
    () async {
      final logs = LogController();
      addTearDown(logs.dispose);
      final records = <LogEvent>[];
      final logging = logs.stream
          .where((r) => r is LogEvent)
          .cast<LogEvent>()
          .listen(records.add);
      addTearDown(logging.cancel);
      final host = Host(log: logs.scope('host'));
      addTearDown(host.dispose);
      host.participant(
        f.work,
        owners: [f.Counting(2)],
        access: const WordAccess(callers: Callers.anyone),
      );
      const bridge = Principal('module', 'proxy');
      host.participant(
        bridge,
        owners: [f.Forwarding(f.work)],
        access: const WordAccess(callers: Callers.anyone),
      );
      host.setAccess(
        address: at('add'),
        access: const WordAccess(callers: warning),
      );
      final caller = host.participant(f.ann);
      final client = f.IBridgeClient(participant: caller, provider: bridge);
      final warnings = <AccessWarning>[];
      final sub = host.registry.accessWarnings.listen(warnings.add);
      addTearDown(sub.cancel);
      await client.forward(amount: 1);
      await pumpEventQueue();
      final warningEvent = warnings.single;
      expect(warningEvent.by, bridge.ofOwner('bridge'));
      expect(warningEvent.cause!.origin!.word, 'module/proxy/bridge.forward');
      expect(warningEvent.word, at('add').toString());
      final event = records.singleWhere(
        (e) => e.message == 'unexpected access',
      );
      expect(event.level, RpcLogLevel.warning);
      expect(event.data!['word'], at('add').toString());
      expect(event.data!.containsKey('params'), isFalse);
    },
  );
}
