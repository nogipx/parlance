import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/contract.dart' show parlanceFeatures;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

part 'stream_kinds_test.g.dart';

@Vocabulary('transfer')
abstract class Transfer {
  @ClientStreamWord('sum', callers: Callers.anyone, whyNot: true)
  Future<int> sum(Stream<int> values, {int initial = 0});

  @BidiStreamWord('double', callers: Callers.anyone)
  Stream<int> doubleValues(Stream<int> values, {int factor = 2});

  @ClientStreamWord('private', callers: Callers({'admin': Access.allow}))
  Future<int> private(Stream<int> values);

  @ClientStreamWord('consume', callers: Callers.anyone)
  Future<void> consume(Stream<int> values);

  @ServerStreamWord('count')
  Stream<int> count({int length = 5});

  @QueryWord('forbidden')
  Future<int> forbidden();
}

class _Owner extends TransferOwnerBase {
  int opened = 0;
  int produced = 0;
  String? blocked;
  CancellationToken? lastExpiry;
  String? lastCaller;
  Future<int> Function(Stream<int>, int)? upload;
  Stream<int> Function(Stream<int>, int)? exchange;

  @override
  String? whyNotSum() => blocked;

  @override
  Future<int> sum(Stream<int> values, {int initial = 0}) {
    opened++;
    lastExpiry = expired;
    lastCaller = by?.selector;
    return upload?.call(values, initial) ??
        values.fold(initial, (a, b) => a + b);
  }

  @override
  Stream<int> doubleValues(Stream<int> values, {int factor = 2}) async* {
    opened++;
    lastExpiry = expired;
    if (exchange != null) {
      yield* exchange!(values, factor);
      return;
    }
    await for (final value in values) {
      yield value * factor;
    }
    yield -1; // Output remains open after input completion.
  }

  @override
  Future<int> private(Stream<int> values) {
    opened++;
    return values.length;
  }

  @override
  Future<void> consume(Stream<int> values) => values.drain<void>();

  @override
  Stream<int> count({int length = 5}) async* {
    for (var i = 0; i < length; i++) {
      produced++;
      yield i;
    }
  }

  @override
  Future<int> forbidden() => ITransferClient.of(
    owner: this,
    target: const Principal('producer'),
  ).sum(Stream.value(1));
}

class _Fixture {
  final host = Host();
  final owner = _Owner();
  final endpoints = <RpcPeerEndpoint>[];
  final guests = <IRemoteParticipant>[];
  late IParticipant producer;
  late IParticipant consumer;
  late ITransferClient client;

  Future<IRemoteParticipant> guest(
    String who, {
    bool owns = false,
    Set<String>? features,
  }) async {
    // Small explicit windows make backpressure observable within a short test.
    final (a, b) = RpcChannelTransport.pair(
      policy: const RpcSecurityPolicy(
        flowControlWindowBytes: 1024,
        initialSendWindowBytes: 1024,
      ),
    );
    final server = RpcPeerEndpoint(transport: a);
    final raw =
        host
                .participant(
                  Principal(who),
                  vocabularies: owns ? [TransferVocabulary.definition] : [],
                )
                .raw
            as LocalParticipant;
    raw.serve(server, features: features);
    server.start();
    final endpoint = RpcPeerEndpoint(transport: b)..start();
    endpoints.addAll([server, endpoint]);
    final p = await Host.joinEndpoint(endpoint);
    guests.add(p);
    return p;
  }

  Future<void> start(bool remoteOwner, bool remoteConsumer) async {
    if (remoteOwner) {
      final p = await guest('producer', owns: true);
      producer = p;
      await p.attach([owner]);
      await p.settle();
    } else {
      producer = host.participant(const Principal('producer'), owners: [owner]);
    }
    consumer = remoteConsumer
        ? await guest('reader')
        : host.participant(const Principal('reader'));
    client = ITransferClient(
      participant: consumer,
      target: const Principal('producer'),
    );
    await consumer.settle();
  }

  Future<void> close() async {
    for (final p in guests.reversed) {
      await p.dispose();
    }
    for (final e in endpoints.reversed) {
      await e.close();
    }
    await host.dispose();
  }
}

Matcher failure(StreamFailureCode code) =>
    isA<StreamFailure>().having((e) => e.code, 'code', code);

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

Map<String, Object?> _emptyTo(() value) => {};
() _emptyFrom(Map<String, Object?> value) => ();
Object? _emptyAt(() value, int index) => null;

void main() {
  for (final remoteOwner in [false, true]) {
    for (final remoteConsumer in [false, true]) {
      group('owner=$remoteOwner consumer=$remoteConsumer', () {
        late _Fixture f;
        setUp(() async {
          f = _Fixture();
          await f.start(remoteOwner, remoteConsumer);
        });
        tearDown(() => f.close());

        test(
          'uploads empty and nonempty input with fixed parameters',
          () async {
            expect(
              await f.client.sum(Stream.fromIterable([1, 2, 3]), initial: 10),
              16,
            );
            expect(await f.client.sum(const Stream.empty(), initial: 7), 7);
            await f.client.consume(Stream.value(1));
            expect(f.owner.lastCaller, 'reader');
            expect(f.owner.lastExpiry!.isCancelled, isTrue);
          },
        );

        test('bidi is lazy and responds before input ends', () async {
          final input = StreamController<int>();
          final output = f.client.doubleValues(input.stream, factor: 3);
          expect(f.owner.opened, 0);
          final iterator = StreamIterator(output);
          final next = iterator.moveNext();
          input.add(4);
          expect(await next, isTrue);
          expect(iterator.current, 12);
          unawaited(input.close());
          expect(await iterator.moveNext(), isTrue);
          expect(iterator.current, -1);
          expect(await iterator.moveNext(), isFalse);
        });

        test('rejects access and availability before invoking owner', () async {
          await expectLater(
            f.client.private(Stream.value(1)),
            throwsA(failure(StreamFailureCode.notPermitted)),
          );
          f.owner.blocked = 'busy';
          f.owner.whenAttached((p) => p.raw.whyNotMayHaveChanged());
          await f.producer.settle();
          await expectLater(
            f.client.sum(Stream.value(1)),
            throwsA(failure(StreamFailureCode.unavailable)),
          );
          expect(f.owner.opened, 0);
        });

        test('cancelled upload stops its source and expires owner', () async {
          final stopped = Completer<void>();
          final input = StreamController<int>(
            onCancel: () => stopped.complete(),
          );
          final token = CancellationToken();
          final result = f.client.sum(input.stream, cancel: token);
          final assertion = expectLater(
            result,
            throwsA(failure(StreamFailureCode.cancelled)),
          );
          await until(() => f.owner.opened == 1);
          token.cancel();
          await assertion;
          await stopped.future.timeout(const Duration(seconds: 2));
          await until(() => f.owner.lastExpiry!.isCancelled);
          unawaited(input.close());
        });

        test('bidi cancellation stops a silent input', () async {
          final stopped = Completer<void>();
          final input = StreamController<int>(
            onCancel: () => stopped.complete(),
          );
          final subscription = f.client
              .doubleValues(input.stream)
              .listen((_) {});
          await until(() => f.owner.opened == 1);
          await subscription.cancel().timeout(const Duration(seconds: 2));
          await stopped.future.timeout(const Duration(seconds: 2));
          await until(() => f.owner.lastExpiry!.isCancelled);
          unawaited(input.close());
        });

        test('input failure terminates the whole exchange', () async {
          await expectLater(
            f.client
                .doubleValues(Stream.error(StateError('input failed')))
                .toList(),
            throwsA(failure(StreamFailureCode.failed)),
          );
        });

        test('early result cancels the still-open input', () async {
          f.owner.upload = (values, initial) async => await values.first;
          final stopped = Completer<void>();
          final input = StreamController<int>(
            onCancel: () => stopped.complete(),
          );
          input.add(42);
          expect(await f.client.sum(input.stream), 42);
          await stopped.future.timeout(const Duration(seconds: 2));
          unawaited(input.close());
        });

        test(
          'cancelling after input completion expires pending result',
          () async {
            final release = Completer<int>();
            f.owner.upload = (values, initial) async {
              await values.drain<void>();
              return release.future;
            };
            final token = CancellationToken();
            final assertion = expectLater(
              f.client.sum(Stream.value(1), cancel: token),
              throwsA(failure(StreamFailureCode.cancelled)),
            );
            await until(() => f.owner.opened == 1);
            await Future<void>.delayed(const Duration(milliseconds: 10));
            token.cancel();
            await assertion;
            await until(() => f.owner.lastExpiry!.isCancelled);
            release.complete(1);
          },
        );

        test('paused output stops producing and resumes in order', () async {
          final received = <int>[];
          final first = Completer<void>();
          final done = Completer<void>();
          late StreamSubscription<int> subscription;
          subscription = f.client.count(length: 10000).listen((v) {
            received.add(v);
            if (v == 0) {
              subscription.pause();
              first.complete();
            }
          }, onDone: done.complete);
          await first.future;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final parked = f.owner.produced;
          expect(parked, lessThan(10000));
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(f.owner.produced, parked);
          subscription.resume();
          await done.future;
          expect(received, List.generate(10000, (i) => i));
        });

        test('bidi output pause reaches the input producer', () async {
          var produced = 0;
          Stream<int> source() async* {
            for (var i = 0; i < 10000; i++) {
              produced++;
              yield i;
            }
          }

          final first = Completer<void>();
          late StreamSubscription<int> sub;
          sub = f.client.doubleValues(source()).listen((_) {
            if (!first.isCompleted) {
              sub.pause();
              first.complete();
            }
          });
          await first.future;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final parked = produced;
          expect(parked, lessThan(10000));
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(produced, parked);
          await sub.cancel();
        });

        test(
          'pre-cancelled upload neither subscribes nor invokes owner',
          () async {
            var listened = false;
            final input = StreamController<int>(
              onListen: () => listened = true,
            );
            final token = CancellationToken()..cancel();
            await expectLater(
              f.client.sum(input.stream, cancel: token),
              throwsA(failure(StreamFailureCode.cancelled)),
            );
            expect(listened, isFalse);
            expect(f.owner.opened, 0);
            unawaited(input.close());
          },
        );

        test('consumer disposal ends an active upload', () async {
          final input = StreamController<int>();
          final assertion = expectLater(
            f.client.sum(input.stream),
            throwsA(isA<StreamFailure>()),
          );
          await until(() => f.owner.opened == 1);
          f.consumer.dispose();
          await assertion;
          await until(() => !input.hasListener);
          unawaited(input.close());
        });

        test('owner failure cancels input and reaches the caller', () async {
          f.owner.upload = (_, _) => Future.error(StateError('owner failed'));
          final input = StreamController<int>();
          await expectLater(
            f.client.sum(input.stream),
            throwsA(failure(StreamFailureCode.failed)),
          );
          await until(() => !input.hasListener);
          unawaited(input.close());
        });

        test(
          'wrong interaction kind is rejected before owner invocation',
          () async {
            await expectLater(
              f.consumer.raw
                  .openStream(
                    'producer/transfer.sum',
                    (initial: 0),
                    TransferClientStream.sum.params,
                    const PlainShape(IntType()),
                  )
                  .toList(),
              throwsA(failure(StreamFailureCode.invalidArgument)),
            );
            expect(f.owner.opened, 0);
          },
        );

        test(
          'malformed input is rejected by the declared element type',
          () async {
            await expectLater(
              f.consumer.raw
                  .openStream(
                    'producer/transfer.sum',
                    (initial: 0),
                    TransferClientStream.sum.params,
                    const PlainShape(IntType()),
                    kind: 'clientStream',
                    input: Stream.value('not an integer'),
                    inputShape: const PlainShape(AnyType()),
                  )
                  .single,
              throwsA(failure(StreamFailureCode.invalidArgument)),
            );
          },
        );

        test('oversized upload element terminates the operation', () async {
          f.producer.raw.defineStream(
            ClientStreamDescriptor(
              'producer/transfer.bytes',
              input: const TextType(),
              type: const IntType(),
              callers: Callers.anyone,
            ),
            (c) => Stream.fromFuture(c.input!.length),
          );
          await f.producer.settle();
          await expectLater(
            f.consumer.raw
                .openStream(
                  'producer/transfer.bytes',
                  (),
                  const RecordShape<()>(
                    {},
                    to: _emptyTo,
                    from: _emptyFrom,
                    get: _emptyAt,
                  ),
                  const PlainShape(IntType()),
                  kind: 'clientStream',
                  input: Stream.value('x' * (300 * 1024)),
                  inputShape: const PlainShape(TextType()),
                )
                .single,
            throwsA(failure(StreamFailureCode.resourceExhausted)),
          );
        });

        test('query cannot initiate an upload', () async {
          await expectLater(f.client.forbidden(), throwsA(isA<CallNotDone>()));
          expect(f.owner.opened, 0);
        });
      });
    }
  }

  test('stream kinds are atomic and input types are contravariant', () {
    final schemas = schemaOf(TransferVocabulary.words);
    final upload = schemas['transfer.sum']! as Map;
    final bidi = schemas['transfer.double']! as Map;
    expect(upload['is'], 'clientStream');
    expect(bidi['is'], 'bidiStream');
    expect(
      entryBreaks(upload, {...upload, 'is': 'bidiStream'}).single.kind,
      BreakKind.word,
    );
    expect(
      entryBreaks(upload, {...upload, 'input': const NumType().toJson()}),
      isEmpty,
    );
    expect(
      entryBreaks({...upload, 'input': const NumType().toJson()}, upload),
      isNotEmpty,
    );
  });

  test('older host rejects input streams without consuming input', () async {
    final f = _Fixture();
    addTearDown(f.close);
    final p = await f.guest(
      'reader',
      features: {...parlanceFeatures}..remove('inputStreams'),
    );
    var listened = false;
    final input = StreamController<int>(onListen: () => listened = true);
    await expectLater(
      ITransferClient(
        participant: p,
        target: const Principal('producer'),
      ).sum(input.stream),
      throwsA(failure(StreamFailureCode.unsupported)),
    );
    expect(listened, isFalse);
    unawaited(input.close());
  });
}
