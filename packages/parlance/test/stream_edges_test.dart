import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/streams.dart' show boundedStream;
import 'package:parlance/src/remote/data_streams.dart' show encodeDataStream;
import 'package:parlance/src/remote/contract.dart' show parlanceFeatures;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

import 'streams_test.dart'
    show DataOwner, IDataClient, DataServerStream, DataVocabulary;

Future<void> turn() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'cancelling in the source factory does not listen to the returned source',
    () async {
      final token = CancellationToken();
      var listened = 0;
      final stream = boundedStream(
        () {
          token.cancel();
          return Stream<int>.multi((out) {
            listened++;
            out.close();
          });
        },
        weigh: (_) => 1,
        cancel: token,
      );
      await expectLater(stream.toList(), throwsA(isA<StreamFailure>()));
      expect(listened, 0);
    },
  );

  test(
    'wire cancellation in the factory does not start another subscription',
    () async {
      var listened = 0;
      final factoryCalled = Completer<void>();
      late StreamSubscription<Object?> sub;
      final stream = encodeDataStream(() {
        unawaited(sub.cancel());
        factoryCalled.complete();
        return Stream<int>.multi((out) {
          listened++;
          out.close();
        });
      });
      sub = stream.listen((_) {});
      await factoryCalled.future;
      await turn();
      expect(listened, 0);
    },
  );

  test(
    'a completed empty paused stream releases its subscription slot',
    () async {
      final host = Host(
        limits: const HostLimits(streams: StreamLimits(subscriptions: 1)),
      );
      addTearDown(host.dispose);
      final owner = DataOwner();
      host.participant(const Principal('producer'), owners: [owner]);
      final client = IDataClient(
        participant: host.participant(const Principal('reader')),
        target: const Principal('producer'),
      );
      final started = Completer<void>();
      final source = StreamController<int>(onListen: started.complete);
      owner.source = (_, _) => source.stream;
      final deliveredDone = Completer<void>();
      final sub = client
          .numbers(start: 0)
          .listen((_) {}, onDone: deliveredDone.complete);
      addTearDown(sub.cancel);
      await started.future;
      sub.pause();
      await source.close();
      expect(deliveredDone.isCompleted, isFalse);
      owner.source = null;
      expect(await client.numbers(start: 7, count: 1).single, 7);
      sub.resume();
      await deliveredDone.future;
    },
  );

  test(
    'a stream owner republishes unchanged whyNot after reconnecting',
    () async {
      final host = Host();
      final servers = <RpcPeerEndpoint>[];
      final transports = <IRpcTransport>[];
      final link = RpcClientConnection(
        transportFactory: (_) async {
          final (client, server) = RpcChannelTransport.pair();
          final endpoint = RpcPeerEndpoint(transport: server);
          host.serve(
            const Principal('producer'),
            endpoint,
            vocabularies: [DataVocabulary.definition],
          );
          endpoint.start();
          servers.add(endpoint);
          transports.add(client);
          return client;
        },
        backoff: const RpcFixedBackoff(Duration(milliseconds: 10)),
      );
      final producer = await Host.join(link);
      addTearDown(() async {
        await producer.dispose();
        await link.dispose();
        for (final server in servers) {
          await server.close();
        }
        await host.dispose();
      });
      final owner = DataOwner()..unavailable = 'sensor offline';
      await producer.attach([owner]);
      await producer.settle();
      final reader = IDataClient(
        participant: host.participant(const Principal('reader')),
        target: const Principal('producer'),
      );
      expect(reader.status(DataServerStream.numbers), isA<WordUnavailable>());
      await transports.last.close();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while ((servers.length < 2 ||
              reader.status(DataServerStream.numbers) is WordMissing) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(servers.length, greaterThanOrEqualTo(2));
      await producer.settle();
      expect(reader.status(DataServerStream.numbers), isA<WordUnavailable>());
      await expectLater(
        reader.numbers(start: 0),
        emitsError(isA<StreamFailure>()),
      );
      expect(owner.opened, 0);
    },
  );

  test(
    'rejoining a host missing current features refuses the session',
    () async {
      final host = Host();
      final servers = <RpcPeerEndpoint>[];
      final transports = <IRpcTransport>[];
      final link = RpcClientConnection(
        transportFactory: (_) async {
          final (client, server) = RpcChannelTransport.pair();
          final endpoint = RpcPeerEndpoint(transport: server);
          final raw =
              host
                      .participant(
                        const Principal('producer'),
                        vocabularies: [DataVocabulary.definition],
                      )
                      .raw
                  as LocalParticipant;
          raw.serve(
            endpoint,
            features: servers.isEmpty
                ? null
                : ({...parlanceFeatures}..remove('streams')),
          );
          endpoint.start();
          servers.add(endpoint);
          transports.add(client);
          return client;
        },
        backoff: const RpcFixedBackoff(Duration(milliseconds: 10)),
      );
      final producer = await Host.join(link);
      addTearDown(() async {
        await producer.dispose();
        await link.dispose();
        for (final server in servers) {
          await server.close();
        }
        await host.dispose();
      });
      final errors = <ParticipantError>[];
      producer.errors.listen(errors.add);
      await producer.attach([DataOwner()..unavailable = 'sensor offline']);
      await producer.settle();
      await transports.last.close();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!errors.any((e) => e.code == ParticipantErrorCode.protocol) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(servers.length, greaterThanOrEqualTo(2));
      expect(producer.raw.synced, isFalse);
      expect(
        errors,
        contains(
          isA<ParticipantError>().having(
            (e) => e.code,
            'code',
            ParticipantErrorCode.protocol,
          ),
        ),
      );
      expect(host.registry.catalog, isEmpty);
    },
  );

  for (final remote in [false, true]) {
    test(
      'a query cannot start stream work (${remote ? 'remote' : 'local'} query)',
      () async {
        final host = Host();
        addTearDown(host.dispose);
        final source = host
            .participant(
              const Principal('source'),
              vocabularies: [const WordSet.open('source')],
            )
            .raw;
        final state = source.defineState(
          StateDescriptor('source/source.changed', type: const BoolType()),
        );
        state.set(false);
        var started = 0;
        source.defineStream(
          ServerStreamDescriptor('source/source.work', type: const IntType()),
          (_) {
            started++;
            state.set(true);
            return Stream.value(1);
          },
        );
        late IRawParticipant queries;
        if (remote) {
          final (client, server) = RpcChannelTransport.pair();
          final endpoint = RpcPeerEndpoint(transport: server);
          host.serve(
            const Principal('queries'),
            endpoint,
            vocabularies: [const WordSet.open('queries')],
          );
          endpoint.start();
          final peer = RpcPeerEndpoint(transport: client)..start();
          final p = await Host.joinEndpoint(peer);
          queries = p.raw;
          addTearDown(() async {
            await p.dispose();
            await peer.close();
            await endpoint.close();
          });
        } else {
          queries = host
              .participant(
                const Principal('queries'),
                vocabularies: [const WordSet.open('queries')],
              )
              .raw;
        }
        queries.defineQuery(
          QueryDescriptor(
            'queries/queries.peek',
            returns: const IntType(),
            askers: Callers.anyone,
          ),
          (_) => queries
              .openStream(
                'source/source.work',
                const <String, Object?>{},
                const PlainShape(AnyType()),
                const PlainShape(IntType()),
              )
              .first,
        );
        await queries.settle();
        final answer = await host
            .participant(const Principal('reader'))
            .raw
            .call('queries/queries.peek', {});
        expect(answer, isA<CallFailed>());
        expect(started, 0);
        expect(source.read('source/source.changed'), false);
      },
    );
  }
}
