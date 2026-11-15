import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/contract.dart' show parlanceFeatures;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

part 'streams_test.g.dart';

class Reading {
  const Reading(this.value);
  final int value;
  factory Reading.fromJson(Map<String, dynamic> json) =>
      Reading(json['value'] as int);
  Map<String, dynamic> toJson() => {'value': value};
}

@Vocabulary('data')
abstract class Data {
  @ServerStreamWord('numbers', whyNot: true)
  Stream<int> numbers({required int start, int count = 3});

  @ServerStreamWord('shared')
  Stream<int> shared();

  @ServerStreamWord('caller')
  Stream<String> caller();

  @ServerStreamWord('nullable')
  Stream<int?> nullable();

  @ServerStreamWord('readings')
  Stream<Reading> readings({required Reading from});

  @ServerStreamWord('private', readers: Callers({'admin': Access.allow}))
  Stream<int> private();
}

class DataOwner extends DataOwnerBase {
  int opened = 0;
  String? unavailable;
  Stream<int> Function(int, int)? source;
  final sharedSource = StreamController<int>.broadcast(sync: true);
  Reading? received;

  DataOwner() {
    onDispose(() => unawaited(sharedSource.close()));
  }

  @override
  Stream<int> numbers({required int start, int count = 3}) {
    opened++;
    return source?.call(start, count) ??
        Stream.fromIterable(List.generate(count, (i) => start + i));
  }

  @override
  String? whyNotNumbers() => unavailable;

  @override
  Stream<int> shared() => sharedSource.stream;

  @override
  Stream<String> caller() async* {
    await Future<void>.value();
    yield by!.selector;
  }

  @override
  Stream<int?> nullable() => Stream.fromIterable([null, 1, null]);

  @override
  Stream<Reading> readings({required Reading from}) {
    received = from;
    return Stream.value(from);
  }

  @override
  Stream<int> private() {
    opened++;
    return Stream.value(1);
  }
}

class _Fixture {
  _Fixture({HostLimits limits = const HostLimits()})
    : host = Host(limits: limits);
  final Host host;
  final owner = DataOwner();
  final endpoints = <RpcPeerEndpoint>[];
  final guests = <IRemoteParticipant>[];
  late IParticipant consumer;
  late IParticipant producer;
  late IDataClient client;

  Future<IRemoteParticipant> guest(
    String name, {
    bool owns = false,
    SessionLimits limits = const SessionLimits(),
    Set<String>? features,
  }) async {
    final (a, b) = RpcChannelTransport.pair();
    final server = RpcPeerEndpoint(transport: a);
    // The tools extension permits simulating an older host's features.
    final raw =
        host
                .participant(
                  Principal(name),
                  vocabularies: owns ? [DataVocabulary.definition] : [],
                )
                .raw
            as LocalParticipant;
    raw.serve(server, limits: limits, features: features);
    server.start();
    final peer = RpcPeerEndpoint(transport: b)..start();
    endpoints.addAll([server, peer]);
    final joined = await Host.joinEndpoint(peer);
    guests.add(joined);
    return joined;
  }

  Future<void> start({
    bool remoteOwner = false,
    bool remoteConsumer = false,
  }) async {
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
    await consumer.settle();
    client = IDataClient(
      participant: consumer,
      target: const Principal('producer'),
    );
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

void main() {
  for (final remoteOwner in [false, true]) {
    for (final remoteConsumer in [false, true]) {
      group('owner ${remoteOwner ? 'remote' : 'local'}, consumer '
          '${remoteConsumer ? 'remote' : 'local'}', () {
        late _Fixture f;
        setUp(() async {
          f = _Fixture();
          await f.start(
            remoteOwner: remoteOwner,
            remoteConsumer: remoteConsumer,
          );
        });
        tearDown(() => f.close());

        test(
          'each listen opens new work, ordered and finite, with defaults',
          () async {
            final stream = f.client.numbers(start: 10);
            expect(f.owner.opened, 0);
            expect(await stream.toList(), [10, 11, 12]);
            expect(f.owner.opened, 1);
            expect(() => stream.listen((_) {}), throwsStateError);
            expect(await f.client.numbers(start: 20, count: 2).toList(), [
              20,
              21,
            ]);
            expect(f.owner.opened, 2);
            expect(f.host.registry.seq, 0);
            expect(f.host.registry.running, isEmpty);
          },
        );

        test('a shared source survives cancellation of one subscriber', () async {
          final a = <int>[];
          final b = <int>[];
          final one = f.client.shared().listen(a.add);
          final two = f.client.shared().listen(b.add);
          // Establish both subscriptions with a data marker, not a fixed delay.
          while (a.isEmpty || b.isEmpty) {
            f.owner.sharedSource.add(1);
            await Future<void>.delayed(Duration.zero);
          }
          await one.cancel();
          final before = a.length;
          f.owner.sharedSource.add(2);
          while (!b.contains(2)) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(a, hasLength(before));
          expect(f.owner.sharedSource.hasListener, isTrue);
          await two.cancel();
        });

        test(
          'async generator runs as the subscriber, and nullable data survives',
          () async {
            expect(await f.client.caller().single, f.consumer.who.selector);
            expect(await f.client.nullable().toList(), [null, 1, null]);
          },
        );

        test('access is checked before invoking the owner', () async {
          await expectLater(
            f.client.private(),
            emitsError(failure(StreamFailureCode.notPermitted)),
          );
          expect(f.owner.opened, 0);
        });

        test(
          'first error terminates data and is stable across connections',
          () async {
            final source = StreamController<int>();
            f.owner.source = (_, _) => source.stream;
            final result = f.client.numbers(start: 0).toList();
            final checked = expectLater(
              result,
              throwsA(failure(StreamFailureCode.failed)),
            );
            while (!source.hasListener) {
              await Future<void>.delayed(Duration.zero);
            }
            source.add(1);
            source.addError(StateError('source failed'));
            source.add(2);
            await checked;
            await source.close();
            expect(source.hasListener, isFalse);
          },
        );

        test('token cancelled before listen invokes no owner', () async {
          final cancel = CancellationToken()..cancel();
          await expectLater(
            f.client.numbers(start: 0, cancel: cancel),
            emitsError(failure(StreamFailureCode.cancelled)),
          );
          expect(f.owner.opened, 0);
        });

        test(
          'cancellation reaches a silent source without waiting for data',
          () async {
            final stopped = Completer<void>();
            final source = StreamController<int>(onCancel: stopped.complete);
            f.owner.source = (_, _) => source.stream;
            final sub = f.client.numbers(start: 0).listen((_) {});
            while (!source.hasListener) {
              await Future<void>.delayed(Duration.zero);
            }
            await sub.cancel();
            await stopped.future.timeout(const Duration(seconds: 3));
            await source.close();
          },
        );

        test('a missing word fails explicitly', () async {
          await expectLater(
            f.consumer.raw.openStream(
              'producer/data.absent',
              const {},
              const PlainShape(RecordType({})),
              const PlainShape(IntType()),
            ),
            emitsError(failure(StreamFailureCode.missing)),
          );
          expect(f.owner.opened, 0);
        });

        test(
          'structured inputs and items stay typed locally and cross the wire',
          () async {
            final input = Reading(42);
            final output = await f.client.readings(from: input).single;
            expect(output.value, 42);
            expect(f.owner.received!.value, 42);
          },
        );

        test(
          'malformed owner elements fail instead of reaching the consumer',
          () async {
            f.producer.raw.defineStream(
              ServerStreamDescriptor(
                'producer/data.broken',
                type: const IntType(),
              ),
              (_) => Stream.value('wrong type'),
            );
            await f.producer.settle();
            await expectLater(
              f.consumer.raw.openStream(
                'producer/data.broken',
                const <String, Object?>{},
                const PlainShape(AnyType()),
                const PlainShape(IntType()),
              ),
              emitsError(failure(StreamFailureCode.invalidArgument)),
            );
          },
        );

        test(
          'cancellation does not wait for an owner parked in an await',
          () async {
            final entered = Completer<void>();
            final release = Completer<void>();
            Stream<int> parked() async* {
              entered.complete();
              await release.future;
              yield 1;
            }

            f.owner.source = (_, _) => parked();
            final sub = f.client.numbers(start: 0).listen((_) {});
            await entered.future;
            try {
              await sub.cancel().timeout(const Duration(seconds: 1));
            } finally {
              release.complete();
            }
          },
        );

        test(
          'invalid parameters are rejected before invoking the owner',
          () async {
            await expectLater(
              f.consumer.raw.openStream(
                'producer/data.numbers',
                const {'start': 'wrong'},
                const PlainShape(AnyType()),
                const PlainShape(IntType()),
              ),
              emitsError(failure(StreamFailureCode.invalidArgument)),
            );
            expect(f.owner.opened, 0);
          },
        );

        test('whyNot prevents new openings and appears in status', () async {
          f.owner.unavailable = 'sensor offline';
          f.owner.whenAttached((p) => p.raw.whyNotMayHaveChanged());
          await f.producer.settle();
          await f.consumer.settle();
          expect(
            f.client.status(DataServerStream.numbers),
            isA<WordUnavailable>(),
          );
          await expectLater(
            f.client.numbers(start: 0),
            emitsError(failure(StreamFailureCode.unavailable)),
          );
          expect(f.owner.opened, 0);
          f.owner.unavailable = null;
          f.owner.whenAttached((p) => p.raw.whyNotMayHaveChanged());
          await f.producer.settle();
          expect(await f.client.numbers(start: 0).toList(), [0, 1, 2]);
        });

        test('withdrawing the owner terminates a silent stream', () async {
          final source = StreamController<int>();
          f.owner.source = (_, _) => source.stream;
          final checked = expectLater(
            f.client.numbers(start: 0),
            emitsError(failure(StreamFailureCode.unavailable)),
          );
          while (!source.hasListener) {
            await Future<void>.delayed(Duration.zero);
          }
          if (f.producer is IRemoteParticipant) {
            await (f.producer as IRemoteParticipant).dispose();
          } else {
            f.producer.dispose();
          }
          await checked;
          expect(source.hasListener, isFalse);
          await source.close();
        });

        test(
          'cancelling a token inside onData is safe and frees the source',
          () async {
            final token = CancellationToken();
            final source = StreamController<int>();
            f.owner.source = (_, _) => source.stream;
            final done = Completer<void>();
            final errors = <Object>[];
            f.client
                .numbers(start: 0, cancel: token)
                .listen(
                  (_) => token.cancel(),
                  onError: errors.add,
                  onDone: done.complete,
                );
            while (!source.hasListener) {
              await Future<void>.delayed(Duration.zero);
            }
            source.add(1);
            await done.future;
            expect(errors, [failure(StreamFailureCode.cancelled)]);
            while (source.hasListener) {
              await Future<void>.delayed(Duration.zero);
            }
            await source.close();
          },
        );

        if (remoteOwner || remoteConsumer) {
          test(
            'connection loss is terminal and does not retry the owner',
            () async {
              final source = StreamController<int>();
              f.owner.source = (_, _) => source.stream;
              final checked = expectLater(
                f.client.numbers(start: 0),
                emitsError(failure(StreamFailureCode.connectionLost)),
              );
              while (!source.hasListener) {
                await Future<void>.delayed(Duration.zero);
              }
              await f.endpoints[1].close();
              await checked;
              while (source.hasListener) {
                await Future<void>.delayed(Duration.zero);
              }
              expect(f.owner.opened, 1);
              await source.close();
            },
          );
        }
      });
    }
  }

  test(
    'an older host is never sent stream definitions or built schemas',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      final p = await f.guest(
        'old',
        owns: true,
        features: {...parlanceFeatures}..remove('streams'),
      );
      final client = IDataClient(
        participant: p,
        target: const Principal('producer'),
      );
      final errors = <ParticipantError>[];
      final sub = p.errors.listen(errors.add);
      await p.settle();
      expect(f.host.registry.mismatches, isEmpty);
      await expectLater(
        client.numbers(start: 0),
        emitsError(failure(StreamFailureCode.unsupported)),
      );
      await expectLater(
        p.attach([f.owner]),
        throwsA(failure(StreamFailureCode.unsupported)),
      );
      expect(f.host.registry.catalog, isEmpty);
      expect(errors, isEmpty);
      await sub.cancel();
    },
  );

  for (final remote in [false, true]) {
    group('limits with ${remote ? 'remote' : 'local'} consumer', () {
      test(
        'one subscription to the participant\'s own word fits a limit of one',
        () async {
          final f = _Fixture(
            limits: const HostLimits(streams: StreamLimits(subscriptions: 1)),
          );
          addTearDown(f.close);
          await f.start(remoteOwner: remote);
          expect(
            await IDataClient(
              participant: f.producer,
              target: const Principal('producer'),
            ).numbers(start: 1).toList(),
            [1, 2, 3],
          );
        },
      );
      test(
        'active subscriptions have a separate limit that is released',
        () async {
          final f = _Fixture(
            limits: const HostLimits(streams: StreamLimits(subscriptions: 1)),
          );
          addTearDown(f.close);
          await f.start(remoteConsumer: remote);
          final source = StreamController<int>.broadcast();
          f.owner.source = (_, _) => source.stream;
          final first = f.client.numbers(start: 0).listen((_) {});
          while (!source.hasListener) {
            await Future<void>.delayed(Duration.zero);
          }
          await expectLater(
            f.client.numbers(start: 1),
            emitsError(failure(StreamFailureCode.resourceExhausted)),
          );
          expect(f.owner.opened, 1);
          await first.cancel();
          while (source.hasListener) {
            await Future<void>.delayed(Duration.zero);
          }
          f.owner.source = null;
          expect(await f.client.numbers(start: 5, count: 1).single, 5);
          await source.close();
        },
      );

      test(
        'oversized elements fail explicitly and cancel the source',
        () async {
          final f = _Fixture(
            limits: const HostLimits(streams: StreamLimits(elementBytes: 4)),
          );
          addTearDown(f.close);
          await f.start(remoteConsumer: remote);
          f.owner.source = (_, _) => Stream.value(123456789012345);
          await expectLater(
            f.client.numbers(start: 0),
            emitsError(failure(StreamFailureCode.resourceExhausted)),
          );
        },
      );

      test(
        'paused delivery preserves order within the bounded queue',
        () async {
          final f = _Fixture();
          addTearDown(f.close);
          await f.start(remoteConsumer: remote);
          final source = StreamController<int>();
          f.owner.source = (_, _) => source.stream;
          final values = <int>[];
          final done = Completer<void>();
          final sub = f.client
              .numbers(start: 0)
              .listen(values.add, onDone: done.complete);
          while (!source.hasListener) {
            await Future<void>.delayed(Duration.zero);
          }
          sub.pause();
          source.add(1);
          source.add(2);
          unawaited(source.close());
          await Future<void>.delayed(Duration.zero);
          expect(values, isEmpty);
          sub.resume();
          await done.future;
          expect(values, [1, 2]);
        },
      );

      test(
        'a broadcast source overflowing while paused fails explicitly',
        () async {
          final f = _Fixture(
            limits: const HostLimits(streams: StreamLimits(bufferItems: 2)),
          );
          addTearDown(f.close);
          await f.start(remoteConsumer: remote);
          final source = StreamController<int>.broadcast();
          f.owner.source = (_, _) => source.stream;
          final errors = <Object>[];
          final done = Completer<void>();
          final sub = f.client
              .numbers(start: 0)
              .listen((_) {}, onError: errors.add, onDone: done.complete);
          while (!source.hasListener) {
            await Future<void>.delayed(Duration.zero);
          }
          sub.pause();
          for (var i = 0; i < 100; i++) {
            source.add(i);
          }
          while (source.hasListener) {
            await Future<void>.delayed(Duration.zero);
          }
          sub.resume();
          await done.future;
          expect(errors, [failure(StreamFailureCode.resourceExhausted)]);
          await source.close();
        },
      );
    });
  }

  test('the streams feature can be required before joining', () async {
    final f = _Fixture();
    addTearDown(f.close);
    final p = await f.guest('old', features: const {'targets'});
    await expectLater(
      Host.joinEndpoint(
        (p as RemoteParticipant).endpoint,
        requires: {'streams'},
      ),
      throwsA(isA<ProtocolMismatch>()),
    );
  });

  test(
    'stream schemas compare parameters as inputs and elements as outputs',
    () {
      final schema = schemaOf(DataVocabulary.words);
      expect((schema['data.numbers']! as Map)['is'], 'serverStream');
      final before = {
        's': {
          'is': 'serverStream',
          'params': const RecordType({'n': Field(IntType())}).toJson(),
          'type': const NumType().toJson(),
        },
      };
      final compatible = {
        's': {
          'is': 'serverStream',
          'params': const RecordType({'n': Field(NumType())}).toJson(),
          'type': const IntType().toJson(),
        },
      };
      expect(schemaBreaks(before, compatible), isEmpty);
      expect(schemaBreaks(compatible, before), isNotEmpty);
    },
  );
}
