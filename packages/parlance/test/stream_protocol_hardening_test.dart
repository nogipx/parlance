import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/contract.dart';
import 'package:parlance/src/remote/data_streams.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

Matcher failure(StreamFailureCode code) =>
    isA<StreamFailure>().having((e) => e.code, 'code', code);

void main() {
  for (final frame in <Map<String, Object?>>[
    {'value': 1, 'failure': 'failed', 'message': 'ambiguous'},
    {'failure': 'failed'},
    {'value': 1, 'unexpected': true},
    {'open': <String, Object?>{}},
  ]) {
    test('rejects ambiguous or malformed frame $frame', () async {
      await expectLater(
        decodeDataStream(Stream.value(WireJson(frame))).toList(),
        throwsA(failure(StreamFailureCode.invalidArgument)),
      );
    });
  }

  test('unknown future failure codes remain terminal failures', () async {
    await expectLater(
      decodeDataStream(
        Stream.value(
          WireJson({'failure': 'futureCode', 'message': 'new peer failure'}),
        ),
      ).toList(),
      throwsA(failure(StreamFailureCode.failed)),
    );
  });

  test('encoder preserves native RPC permission refusals', () async {
    await expectLater(
      decodeDataStream(
        encodeDataStream(
          () => throw const RpcStatusException(
            RpcStatus.permissionDenied,
            'wrong principal',
          ),
        ),
      ).toList(),
      throwsA(failure(StreamFailureCode.notPermitted)),
    );
  });

  test('RPC resource exhaustion retains its semantic failure code', () async {
    await expectLater(
      decodeDataStream(
        Stream.error(
          RpcStatusException(RpcStatus.resourceExhausted, 'RPC window limit'),
        ),
      ).toList(),
      throwsA(failure(StreamFailureCode.resourceExhausted)),
    );
  });

  test(
    'endpoint shutdown is connection loss rather than user cancellation',
    () async {
      await expectLater(
        decodeDataStream(
          Stream.error(RpcCancelledException('Endpoint closed')),
        ).toList(),
        throwsA(failure(StreamFailureCode.connectionLost)),
      );
    },
  );

  test('an expired RPC call scope ends an idle exchange', () async {
    final context = RpcContext.empty().withTimeout(
      const Duration(milliseconds: 20),
    );
    final requests = StreamController<WireJson>();
    final output = receiveExchange(
      requests.stream,
      (_, _) => const Stream.empty(),
      context: context,
    );
    await expectLater(
      output.toList().timeout(const Duration(seconds: 1)),
      throwsA(failure(StreamFailureCode.cancelled)),
    );
    expect(requests.hasListener, isFalse);
    unawaited(requests.close());
  });

  test('an already-cancelled RPC never subscribes to its input', () async {
    var listened = false;
    final input = StreamController<WireJson>(onListen: () => listened = true);
    final context = RpcContext.empty().withCancellation(
      RpcCancellationToken.cancelled(),
    );
    await expectLater(
      receiveExchange(
        input.stream,
        (_, _) => const Stream.empty(),
        context: context,
      ).toList(),
      throwsA(failure(StreamFailureCode.cancelled)),
    );
    expect(listened, isFalse);
    unawaited(input.close());
  });

  test('an opening header must be the only field of its frame', () async {
    final input = Stream.value(
      WireJson({'open': <String, Object?>{}, 'value': 3}),
    );
    var invoked = false;
    await expectLater(
      receiveExchange(input, (_, _) {
        invoked = true;
        return Stream.value(1);
      }).toList(),
      throwsA(failure(StreamFailureCode.invalidArgument)),
    );
    expect(invoked, isFalse);
  });

  test('all native stream forms refuse a forged participant', () async {
    final host = Host();
    final (a, b) = RpcChannelTransport.pair();
    final server = RpcPeerEndpoint(transport: a);
    host.serve(const Principal('reader'), server);
    server.start();
    final endpoint = RpcPeerEndpoint(transport: b)..start();
    addTearDown(() async {
      await endpoint.close();
      await server.close();
      await host.dispose();
    });
    final caller = ParlanceContractPeerCaller(endpoint);
    final header = {
      'name': 'source/probe.values',
      'params': <String, Object?>{},
      'as': const Principal('admin').toJson(),
    };
    for (final kind in ['serverStream', 'clientStream', 'bidiStream']) {
      final requests = Stream.value(WireJson({'open': header}));
      final responses = switch (kind) {
        'clientStream' => Stream.fromFuture(caller.uploadData(requests)),
        'bidiStream' => caller.exchangeData(requests),
        _ => caller.openData(WireJson(header)),
      };
      await expectLater(
        decodeDataStream(responses).toList(),
        throwsA(failure(StreamFailureCode.notPermitted)),
      );
    }
  });

  test(
    'a remote owner validates its opening before invoking a handler',
    () async {
      final host = Host();
      final (a, b) = RpcChannelTransport.pair();
      final server = RpcPeerEndpoint(transport: a);
      host.serve(
        const Principal('source'),
        server,
        vocabularies: [const WordSet.open('probe')],
      );
      server.start();
      final endpoint = RpcPeerEndpoint(transport: b)..start();
      final owner = await Host.joinEndpoint(endpoint);
      addTearDown(() async {
        await owner.dispose();
        await endpoint.close();
        await server.close();
        await host.dispose();
      });
      var invoked = 0;
      owner.raw.defineStream(
        ServerStreamDescriptor('source/probe.values', type: const IntType()),
        (_) {
          invoked++;
          return Stream.value(1);
        },
      );
      await owner.settle();
      final caller = ParlanceOwnerContractPeerCaller(server);
      final valid = <String, Object?>{
        'name': 'source/probe.values',
        'params': <String, Object?>{},
        'id': 'probe',
        'cause': Cause(const Principal('reader')).toJson(),
      };
      for (final invalid in [
        {...valid, 'id': 1},
        {...valid, 'params': 'bad'},
        {...valid, 'cause': <String, Object?>{}},
        {...valid, 'traceparent': 42},
      ]) {
        await expectLater(
          decodeDataStream(caller.openData(WireJson(invalid))).toList(),
          throwsA(failure(StreamFailureCode.invalidArgument)),
        );
      }
      expect(invoked, 0);
      expect(
        await decodeDataStream(caller.openData(WireJson(valid))).toList(),
        [1],
      );
      expect(invoked, 1);
    },
  );

  for (final ownerSide in [false, true]) {
    test(
      'native deadline frees a pending ${ownerSide ? 'owner' : 'host'} opening',
      () async {
        final host = Host();
        final (a, b) = RpcChannelTransport.pair();
        final server = RpcPeerEndpoint(transport: a);
        host.serve(
          const Principal('reader'),
          server,
          limits: const SessionLimits(streams: StreamLimits(subscriptions: 1)),
        );
        server.start();
        final endpoint = RpcPeerEndpoint(transport: b)..start();
        final joined = ownerSide ? await Host.joinEndpoint(endpoint) : null;
        final input = StreamController<WireJson>();
        addTearDown(() async {
          if (joined != null) await joined.dispose();
          await endpoint.close();
          await server.close();
          unawaited(input.close());
          await host.dispose();
        });
        Stream<WireJson> invoke(
          Stream<WireJson> requests, {
          RpcContext? context,
        }) => ownerSide
            ? ParlanceOwnerContractPeerCaller(
                server,
              ).exchangeData(requests, context: context)
            : ParlanceContractPeerCaller(
                endpoint,
              ).exchangeData(requests, context: context);
        await expectLater(
          decodeDataStream(
            invoke(
              input.stream,
              context: RpcContext.empty().withTimeout(
                const Duration(milliseconds: 50),
              ),
            ),
          ).toList().timeout(const Duration(seconds: 1)),
          throwsA(failure(StreamFailureCode.cancelled)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(input.hasListener, isFalse);
        await expectLater(
          decodeDataStream(
            invoke(
              Stream.value(
                WireJson({
                  'open': {
                    'name': 'missing.word',
                    'params': <String, Object?>{},
                    if (ownerSide) 'id': 'probe',
                    if (ownerSide)
                      'cause': Cause(const Principal('reader')).toJson(),
                  },
                }),
              ),
            ),
          ).toList().timeout(const Duration(seconds: 1)),
          throwsA(
            isA<StreamFailure>().having(
              (e) => e.code,
              'code',
              anyOf(StreamFailureCode.missing, StreamFailureCode.unavailable),
            ),
          ),
        );
      },
    );

    for (final firstKind in ['clientStream', 'bidiStream']) {
      test(
        'pending $firstKind counts toward ${ownerSide ? 'owner' : 'host'} quota and releases on cancel',
        () async {
          final host = Host();
          final entered = Completer<void>();
          final (a, b) = RpcChannelTransport.pair();
          final server = RpcPeerEndpoint(transport: a);
          host.serve(
            const Principal('reader'),
            server,
            vocabularies: ownerSide ? [const WordSet.open('probe')] : [],
            limits: const SessionLimits(
              streams: StreamLimits(subscriptions: 1),
            ),
          );
          server.start();
          final endpoint = RpcPeerEndpoint(transport: b)..start();
          final joined = ownerSide ? await Host.joinEndpoint(endpoint) : null;
          final producer =
              joined ??
              host.participant(
                const Principal('source'),
                vocabularies: [const WordSet.open('probe')],
              );
          producer.raw.defineStream(
            ClientStreamDescriptor(
              WordAddress(producer.who.whole, 'probe.upload').toString(),
              input: const IntType(),
              type: const IntType(),
              callers: Callers.anyone,
            ),
            (c) {
              entered.complete();
              return Stream.fromFuture(c.input!.length);
            },
          );
          await producer.settle();
          final hostCaller = ParlanceContractPeerCaller(endpoint);
          final ownerCaller = ParlanceOwnerContractPeerCaller(server);
          Stream<WireJson> invoke(
            String kind,
            Stream<WireJson> requests,
            RpcContext context,
          ) {
            if (kind == 'clientStream') {
              return Stream.fromFuture(
                ownerSide
                    ? ownerCaller.uploadData(requests, context: context)
                    : hostCaller.uploadData(requests, context: context),
              );
            }
            return ownerSide
                ? ownerCaller.exchangeData(requests, context: context)
                : hostCaller.exchangeData(requests, context: context);
          }

          final input = StreamController<WireJson>();
          final secondInput = StreamController<WireJson>();
          Map<String, Object?> opening(String word) => {
            'open': {
              'name': word,
              'params': <String, Object?>{},
              if (ownerSide) 'id': 'probe',
              if (ownerSide) 'cause': Cause(const Principal('reader')).toJson(),
            },
          };
          // rpc_dart client streams are cold on the wire until their first
          // request. Bidi calls open on listen, before their first request.
          if (firstKind == 'clientStream') {
            input.add(
              WireJson(
                opening(
                  WordAddress(producer.who.whole, 'probe.upload').toString(),
                ),
              ),
            );
          }
          final token = RpcCancellationToken();
          final first = decodeDataStream(
            invoke(
              firstKind,
              input.stream,
              RpcContext.empty().withCancellation(token),
            ),
          ).listen((_) {}, onError: (Object _) {});
          addTearDown(() async {
            token.cancel();
            await first.cancel();
            if (joined != null) await joined.dispose();
            await endpoint.close();
            await server.close();
            unawaited(input.close());
            unawaited(secondInput.close());
            await host.dispose();
          });
          if (firstKind == 'clientStream') {
            await entered.future;
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          final otherKind = firstKind == 'clientStream'
              ? 'bidiStream'
              : 'clientStream';
          if (otherKind == 'clientStream') {
            secondInput.add(WireJson(opening('missing.word')));
          }
          await expectLater(
            decodeDataStream(
              invoke(otherKind, secondInput.stream, RpcContext.empty()),
            ).toList().timeout(const Duration(seconds: 1)),
            throwsA(failure(StreamFailureCode.resourceExhausted)),
          );
          token.cancel();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          final header = {
            'open': {
              'name': 'missing.word',
              'params': <String, Object?>{},
              if (ownerSide) 'id': 'probe',
              if (ownerSide) 'cause': Cause(const Principal('reader')).toJson(),
            },
          };
          await expectLater(
            decodeDataStream(
              invoke(
                otherKind,
                Stream.value(WireJson(header)),
                RpcContext.empty(),
              ),
            ).toList().timeout(const Duration(seconds: 1)),
            throwsA(
              isA<StreamFailure>().having(
                (e) => e.code,
                'code',
                anyOf(StreamFailureCode.missing, StreamFailureCode.unavailable),
              ),
            ),
          );
        },
      );
    }
  }
}
