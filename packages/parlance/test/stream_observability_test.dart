import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

import '../example/streams/words.dart';

class _Store extends DocumentStore {
  Stream<String> Function(Stream<String>)? processing;
  @override
  Stream<String> preview(Stream<String> lines, {String prefix = ''}) =>
      processing?.call(lines) ?? super.preview(lines, prefix: prefix);
}

class _Fixture {
  final logs = LogController();
  late final host = Host(log: logs.scope('parlance'));
  final store = _Store();
  final peers = <RpcPeerEndpoint>[];
  final guests = <IRemoteParticipant>[];
  final events = <StreamEvent>[];
  final records = <LogRecord>[];
  final handles = <StreamSubscription<Object?>>[];
  late IParticipant reader;
  late IParticipant owner;
  late IDocumentsClient client;

  Future<IRemoteParticipant> guest(String name, {bool owns = false}) async {
    final (a, b) = RpcChannelTransport.pair();
    final server = RpcPeerEndpoint(transport: a);
    host.serve(
      Principal(name),
      server,
      vocabularies: owns ? [DocumentsVocabulary.definition] : [],
    );
    server.start();
    final endpoint = RpcPeerEndpoint(transport: b)..start();
    peers.addAll([server, endpoint]);
    final joined = await Host.joinEndpoint(endpoint);
    guests.add(joined);
    return joined;
  }

  Future<void> start(bool remoteOwner, bool remoteReader) async {
    handles.add(logs.stream.listen(records.add));
    handles.add(host.registry.streamEvents.listen(events.add));
    if (remoteOwner) {
      final joined = await guest('store', owns: true);
      await joined.attach([store]);
      await joined.settle();
      owner = joined;
    } else {
      owner = host.participant(const Principal('store'), owners: [store]);
    }
    reader = remoteReader
        ? await guest('editor')
        : host.participant(const Principal('editor'));
    client = IDocumentsClient(
      participant: reader,
      target: const Principal('store'),
    );
  }

  Future<void> close() async {
    for (final guest in guests.reversed) {
      await guest.dispose();
    }
    for (final peer in peers.reversed) {
      await peer.close();
    }
    await host.dispose();
    for (final handle in handles) {
      await handle.cancel();
    }
    logs.dispose();
  }
}

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

void main() {
  test('journal withdrawal during opening preserves lifecycle order', () async {
    final f = _Fixture();
    await f.start(false, false);
    addTearDown(f.close);
    var invoked = false;
    f.store.processing = (_) {
      invoked = true;
      return const Stream.empty();
    };
    final journalEvents = <String>[];
    final observer = f.host.registry.journal.listen((entry) {
      if (entry case JournalDiagnostic(:final event)) {
        if (event.startsWith('stream.')) journalEvents.add(event);
        if (event == 'stream.opened') f.owner.dispose();
      }
    });
    addTearDown(observer.cancel);
    await expectLater(
      f.client.preview(const Stream.empty()).toList(),
      throwsA(isA<StreamFailure>()),
    );
    expect(invoked, isFalse);
    expect(f.host.registry.activeStreams, isEmpty);
    expect(f.events.map((e) => e.kind), [
      StreamEventKind.opened,
      StreamEventKind.closed,
    ]);
    expect(journalEvents, ['stream.opened', 'stream.closed']);
  });

  test('disposal from an opened event releases the operation once', () async {
    final f = _Fixture();
    await f.start(false, false);
    addTearDown(f.close);
    var invoked = false;
    f.store.processing = (_) {
      invoked = true;
      return const Stream.empty();
    };
    Future<void>? closing;
    final observer = f.host.registry.streamEvents.listen((event) {
      if (event.kind == StreamEventKind.opened) closing = f.host.dispose();
    });
    await expectLater(
      f.client.preview(const Stream.empty()).toList(),
      throwsA(isA<StreamFailure>()),
    );
    expect(closing, isNotNull);
    await closing!.timeout(const Duration(seconds: 1));
    expect(invoked, isFalse);
    expect(f.host.registry.activeStreams, isEmpty);
    expect(f.events.map((e) => e.kind), [
      StreamEventKind.opened,
      StreamEventKind.closed,
    ]);
    await observer.cancel();
  });

  test(
    'withdrawing a word inside availability prevents handler invocation',
    () async {
      final host = Host();
      addTearDown(host.dispose);
      final owner = host.participant(
        const Principal('source'),
        vocabularies: [const WordSet.open('source')],
      );
      final reader = host.participant(const Principal('reader'));
      late IHandle definition;
      var invoked = false;
      definition = owner.raw.defineStream(
        ServerStreamDescriptor('source/source.values', type: const IntType()),
        (_) {
          invoked = true;
          return Stream.value(1);
        },
        whyNot: () {
          definition.dispose();
          return null;
        },
      );
      await expectLater(
        reader.raw
            .openStream(
              'source/source.values',
              (),
              const RecordShape<()>({}, to: _to, from: _from, get: _at),
              const PlainShape(IntType()),
            )
            .toList(),
        throwsA(
          isA<StreamFailure>().having(
            (e) => e.code,
            'code',
            StreamFailureCode.unavailable,
          ),
        ),
      );
      expect(invoked, isFalse);
      expect(host.registry.activeStreams, isEmpty);
    },
  );

  for (final remoteOwner in [false, true]) {
    for (final remoteReader in [false, true]) {
      group('owner=$remoteOwner reader=$remoteReader', () {
        late _Fixture f;
        setUp(() async {
          f = _Fixture();
          await f.start(remoteOwner, remoteReader);
        });
        tearDown(() => f.close());

        test(
          'uploads count both directions and release usage after completion',
          () async {
            final input = StreamController<String>();
            final result = f.client.save(input.stream, name: 'notes');
            await until(() => f.host.registry.activeStreams.isNotEmpty);
            final initial = f.host.registry.activeStreams.single;
            expect(initial.kind, 'clientStream');
            expect(initial.by.selector, 'editor');
            expect(
              f.host.registry.usesOf('store/documents.save').single.listening,
              1,
            );
            input.add('secret payload one');
            input.add('secret payload two');
            await until(
              () => f.host.registry.activeStreams.single.input.items == 2,
            );
            expect(initial.input.items, 0, reason: 'snapshots are immutable');
            unawaited(input.close());
            expect(await result, 2);
            await until(
              () => f.events
                  .where((e) => e.kind == StreamEventKind.closed)
                  .isNotEmpty,
            );
            final ended = f.events.last.stream;
            expect(ended.input.items, 2);
            expect(ended.output.items, 1);
            expect(ended.input.bytes, greaterThan(ended.output.bytes));
            expect(ended.termination, StreamTermination.completed);
            expect(ended.failure, isNull);
            expect(ended.input.closed, isTrue);
            expect(f.host.registry.activeStreams, isEmpty);
            final usage = f.host.registry.usesOf('store/documents.save').single;
            expect(usage.reads, 1);
            expect(usage.listening, 0);
            await Future<void>.delayed(Duration.zero);
            final spans = f.records.whereType<LogSpan>().where(
              (s) => s.data?['stream'] == 'clientStream',
            );
            expect(spans, hasLength(1));
            expect(spans.single.data!['inputItems'], 2);
            expect(
              spans.single.data.toString(),
              isNot(contains('secret payload')),
            );
          },
        );

        test(
          'raw stream arguments have the same rules locally and remotely',
          () async {
            for (final kind in ['unknown', 'clientStream', 'bidiStream']) {
              await expectLater(
                f.reader.raw
                    .openStream(
                      'store/documents.read',
                      (name: 'notes'),
                      DocumentsServerStream.read.params,
                      const PlainShape(TextType()),
                      kind: kind,
                    )
                    .toList(),
                throwsA(
                  isA<StreamFailure>().having(
                    (e) => e.code,
                    'code',
                    StreamFailureCode.invalidArgument,
                  ),
                ),
              );
            }
            await expectLater(
              f.reader.raw
                  .openStream(
                    'store/documents.read',
                    (name: 'notes'),
                    DocumentsServerStream.read.params,
                    const PlainShape(TextType()),
                    input: Stream.value('unexpected input'),
                  )
                  .toList(),
              throwsA(
                isA<StreamFailure>().having(
                  (e) => e.code,
                  'code',
                  StreamFailureCode.invalidArgument,
                ),
              ),
            );
          },
        );

        test('raw JSON input needs no local Dart shape', () async {
          expect(
            await f.reader.raw
                .openStream(
                  'store/documents.save',
                  (name: 'notes'),
                  DocumentsClientStream.save.params,
                  const PlainShape(IntType()),
                  kind: 'clientStream',
                  input: Stream.fromIterable(['one', 'two']),
                )
                .single,
            2,
          );
        });

        test(
          'a listener sees operations queued before it subscribed',
          () async {
            final pending = f.client.read(name: 'missing').toList();
            final observed = <StreamEvent>[];
            final observer = f.host.registry.streamEvents.listen(observed.add);
            await pending;
            expect(observed.map((e) => e.kind), [
              StreamEventKind.opened,
              StreamEventKind.closed,
            ]);
            await observer.cancel();
          },
        );

        test('a stream opened by a command is its child span', () async {
          f.owner.raw.defineCommand(
            CommandDescriptor(
              'store/documents.run',
              callers: Callers.anyone,
              returns: const IntType(),
            ),
            (_) => IDocumentsClient(
              participant: f.owner,
              target: const Principal('store'),
            ).save(Stream.value('line'), name: 'notes'),
          );
          await f.owner.settle();
          final result = await f.reader.raw.call(
            'store/documents.run',
            {},
            id: 'root',
          );
          expect(result, isA<CallDone<Object?>>());
          await Future<void>.delayed(Duration.zero);
          final command = f.records.whereType<LogSpan>().singleWhere(
            (s) => s.name == 'store/documents.run',
          );
          final stream = f.records.whereType<LogSpan>().singleWhere(
            (s) => s.name == 'store/documents.save',
          );
          expect(stream.parentSpanId, command.spanId);
          expect(stream.traceId, command.traceId);
        });

        test('commands from a stream owner follow the stream trace', () async {
          f.owner.raw.defineCommand(
            CommandDescriptor('store/documents.touch', callers: Callers.anyone),
            (_) {},
          );
          await f.owner.settle();
          f.store.processing = (_) async* {
            final result = await f.owner.raw.call(
              'store/documents.touch',
              {},
              id: 'touch',
            );
            expect(result, isA<CallDone<Object?>>());
            yield 'done';
          };
          expect(await f.client.preview(const Stream.empty()).toList(), [
            'done',
          ]);
          await Future<void>.delayed(Duration.zero);
          final stream = f.records.whereType<LogSpan>().singleWhere(
            (s) => s.name == 'store/documents.preview',
          );
          final command = f.records.whereType<LogSpan>().singleWhere(
            (s) => s.name == 'store/documents.touch',
          );
          expect(command.parentSpanId, stream.spanId);
          expect(command.traceId, stream.traceId);
        });

        test(
          'silent cancellation is distinct from normal completion',
          () async {
            final input = StreamController<String>();
            final subscription = f.client.preview(input.stream).listen((_) {});
            await until(() => f.host.registry.activeStreams.isNotEmpty);
            await subscription.cancel();
            await until(
              () => f.events
                  .where((e) => e.kind == StreamEventKind.closed)
                  .isNotEmpty,
            );
            expect(
              f.events.last.stream.termination,
              StreamTermination.cancelled,
            );
            expect(f.host.registry.activeStreams, isEmpty);
            expect(
              f.host.registry
                  .usesOf('store/documents.preview')
                  .single
                  .listening,
              0,
            );
            unawaited(input.close());
          },
        );

        test(
          'refused admission is observable without invoking a source',
          () async {
            final input = StreamController<String>();
            await expectLater(
              f.reader.raw
                  .openStream(
                    'store/documents.missing',
                    (),
                    const RecordShape<()>({}, to: _to, from: _from, get: _at),
                    const PlainShape(TextType()),
                  )
                  .toList(),
              throwsA(isA<StreamFailure>()),
            );
            expect(f.events.single.kind, StreamEventKind.rejected);
            expect(f.events.single.stream.failure, StreamFailureCode.missing);
            expect(f.host.registry.activeStreams, isEmpty);
            expect(f.host.registry.usesOf('store/documents.missing'), isEmpty);
            unawaited(input.close());
          },
        );

        test('a paused diagnostic listener has a bounded queue', () async {
          final errors = <Object>[];
          final done = Completer<void>();
          final observer = f.host.registry.streamEvents.listen(
            (_) {},
            onError: errors.add,
            onDone: done.complete,
          );
          observer.pause();
          for (var i = 0; i < 100; i++) {
            await f.client.read(name: 'missing').drain<void>();
          }
          expect(f.host.registry.activeStreams, isEmpty);
          observer.resume();
          await done.future;
          expect(errors, [
            isA<StreamFailure>().having(
              (e) => e.code,
              'code',
              StreamFailureCode.resourceExhausted,
            ),
          ]);
          await observer.cancel();
        });

        if (!remoteOwner && !remoteReader) {
          test('snapshot exposes pause and a bounded output queue', () async {
            f.store.processing = (_) =>
                Stream.fromIterable(List.generate(100, (i) => '$i'));
            final first = Completer<void>();
            final done = Completer<void>();
            late StreamSubscription<String> sub;
            sub = f.client.preview(const Stream.empty()).listen((_) {
              if (!first.isCompleted) {
                sub.pause();
                first.complete();
              }
            }, onDone: done.complete);
            await first.future;
            await until(
              () =>
                  f.host.registry.activeStreams.single.output.pendingItems > 0,
            );
            final snapshot = f.host.registry.activeStreams.single;
            expect(snapshot.output.paused, isTrue);
            expect(snapshot.output.pendingItems, 1);
            expect(snapshot.output.delivered, 1);
            sub.resume();
            await done.future;
            expect(f.events.last.stream.output.items, 100);
            expect(f.events.last.stream.output.delivered, 100);
          });
        }

        test(
          'source failure produces one failed terminal observation',
          () async {
            f.store.processing = (_) =>
                Stream.error(StateError('owner failed'));
            await expectLater(
              f.client.preview(const Stream.empty()).toList(),
              throwsA(isA<StreamFailure>()),
            );
            expect(f.events.map((e) => e.kind), [
              StreamEventKind.opened,
              StreamEventKind.closed,
            ]);
            expect(f.events.last.stream.termination, StreamTermination.failed);
            expect(f.events.last.stream.failure, StreamFailureCode.failed);
            expect(f.host.registry.activeStreams, isEmpty);
          },
        );

        test(
          'observer cancellation during opening never invokes the owner',
          () async {
            var invoked = false;
            f.store.processing = (_) {
              invoked = true;
              return const Stream.empty();
            };
            final token = CancellationToken();
            final watcher = f.host.registry.streamEvents.listen((event) {
              if (event.kind == StreamEventKind.opened) token.cancel();
            });
            await expectLater(
              f.client.preview(const Stream.empty(), cancel: token).toList(),
              throwsA(isA<StreamFailure>()),
            );
            await watcher.cancel();
            await until(() => f.host.registry.activeStreams.isEmpty);
            // A remote caller's cancellation must cross the transport; the
            // owner may start before that notice arrives.
            if (!remoteReader) expect(invoked, isFalse);
          },
        );
      });
    }
  }
}

Map<String, Object?> _to(() value) => {};
() _from(Map<String, Object?> value) => ();
Object? _at(() value, int index) => null;
