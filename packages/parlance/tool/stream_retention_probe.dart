/// Forced-GC checks. Run with:
/// fvm dart --enable-vm-service=0 run tool/stream_retention_probe.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:parlance/src/registry/streams.dart';
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/data_streams.dart';
import 'package:parlance/src/remote/contract.dart' show WireJson;
import 'package:rpc_dart/rpc_dart.dart'
    show RpcChannelTransport, RpcPeerEndpoint, RpcContext, RpcCancellationToken;
import 'package:rpc_dart/internal.dart' show StreamBridge, StreamSource;

import '../test/streams_test.dart'
    show DataOwner, Reading, dataWords, IDataClient;

import '../example/streams/words.dart';

class _Payload {
  final bytes = Uint8List(128 * 1024)..[0] = 1;
}

typedef _Check = ({String name, WeakReference<Object> weak, bool collected});
final _held = <Object>[];
final _checks = <_Check>[];
final _cleanup = <Future<void> Function()>[];
final _resources = <({String name, Object value, List<String> empty})>[];

class _Vm {
  _Vm(this.socket) {
    socket.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      if (message['id'] case final String id) {
        _pending.remove(id)?.complete(message);
      }
    });
  }
  final WebSocket socket;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  var _id = 0;
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final id = '${++_id}';
    final result = Completer<Map<String, dynamic>>();
    _pending[id] = result;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return result.future.then((message) {
      if (message.containsKey('error')) throw StateError('$message');
      return (message['result'] as Map).cast<String, dynamic>();
    });
  }
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void _controls() {
  final dead = _Payload();
  _checks.add((
    name: 'unreferenced control',
    weak: WeakReference(dead),
    collected: true,
  ));
  final live = _Payload();
  final stream = LazyDataStream<int>(() => Stream.value(live.bytes.length));
  _held.add(stream);
  _checks.add((
    name: 'unopened stream control',
    weak: WeakReference(live),
    collected: false,
  ));
}

Future<void> _lazy() async {
  final payload = _Payload();
  final stream = LazyDataStream<int>(() => Stream.value(payload.bytes.length));
  _checks.add((
    name: 'consumed lazy factory',
    weak: WeakReference(payload),
    collected: true,
  ));
  await stream.drain<void>();
  _held.add(stream);
}

Future<void> _closedBridge(String which) async {
  final payload = _Payload();
  _checks.add((
    name: 'closed bridge $which',
    weak: WeakReference(payload),
    collected: true,
  ));
  final stream = boundedStream<int>(
    which == 'factory'
        ? () => Stream.value(payload.bytes.length)
        : () => Stream.value(1),
    weigh: which == 'weigher' ? (_) => payload.bytes.first : (_) => 1,
    onClosed: which == 'onClosed'
        ? (_, _, _) {
            payload.bytes.first;
          }
        : null,
  );
  await stream.drain<void>();
  _held.add(stream);
}

Future<void> _cancelledQueue() async {
  final payload = _Payload();
  final source = StreamController<_Payload>();
  final token = CancellationToken();
  final stream = boundedStream(
    () => source.stream,
    weigh: (_) => 1,
    cancel: token,
  );
  final sub = stream.listen((_) {});
  await _pump();
  sub.pause();
  source.add(payload);
  await _pump();
  await sub.cancel();
  await source.close();
  _held.addAll([stream, sub, source, token]);
  _checks.add((
    name: 'cancelled paused queue',
    weak: WeakReference(payload),
    collected: true,
  ));
}

Future<void> _wireFactory() async {
  final payload = _Payload();
  final stream = encodeDataStream(() => Stream.value(payload.bytes.length));
  await stream.drain<void>();
  _held.add(stream);
  _checks.add((
    name: 'completed wire encoder',
    weak: WeakReference(payload),
    collected: true,
  ));
}

Future<void> _cancelDuringWeigh() async {
  final payload = _Payload();
  final source = StreamController<_Payload>();
  final token = CancellationToken();
  final stream = boundedStream(
    () => source.stream,
    cancel: token,
    weigh: (_) {
      token.cancel();
      return 1;
    },
  );
  final done = Completer<void>();
  final sub = stream.listen(
    (_) {},
    onError: (Object _) {},
    onDone: done.complete,
  );
  await _pump();
  source.add(payload);
  await done.future;
  await source.close();
  _held.addAll([stream, sub, source, token]);
  _checks.add((
    name: 'cancellation during element weighing',
    weak: WeakReference(payload),
    collected: true,
  ));
}

class _Input extends Reading {
  _Input() : super(42);
  final bytes = Uint8List(128 * 1024)..[0] = 1;
}

class _Owner extends DataOwner {
  StreamController<Reading>? readingSource;
  @override
  Stream<Reading> readings({required Reading from}) =>
      readingSource?.stream ?? Stream.value(from);
}

Future<IRemoteParticipant> _join(
  Host host,
  String name,
  List<IRemoteParticipant> guests,
  List<RpcPeerEndpoint> endpoints, {
  bool owns = false,
  WordSet? words,
}) async {
  final (a, b) = RpcChannelTransport.pair();
  final server = RpcPeerEndpoint(transport: a);
  final session = host.serve(
    Principal(name),
    server,
    vocabularies: owns ? [words ?? dataWords] : [],
  );
  _resources.add((
    name: 'session $name ${_resources.length}',
    value: session,
    empty: ['_data', '_providedData', '_servingData'],
  ));
  server.start();
  final peer = RpcPeerEndpoint(transport: b)..start();
  endpoints.addAll([server, peer]);
  final guest = await Host.joinEndpoint(peer);
  guests.add(guest);
  return guest;
}

Future<void> _publicPath(
  bool remoteOwner,
  bool remoteConsumer,
  String ending,
) async {
  final label =
      'owner=${remoteOwner ? 'rpc' : 'local'} '
      'consumer=${remoteConsumer ? 'rpc' : 'local'} $ending';
  final host = Host();
  final observations = <StreamEvent>[];
  final observing = host.registry.streamEvents.listen(observations.add);
  final owner = _Owner();
  final guests = <IRemoteParticipant>[];
  final endpoints = <RpcPeerEndpoint>[];
  late IParticipant producer;
  if (remoteOwner) {
    final guest = await _join(host, 'producer', guests, endpoints, owns: true);
    await guest.attach([owner]);
    producer = guest;
  } else {
    producer = host.participant(const Principal('producer'), owners: [owner]);
  }
  final consumer = remoteConsumer
      ? await _join(host, 'consumer', guests, endpoints)
      : host.participant(const Principal('consumer'));
  final token = CancellationToken();
  if (ending == 'complete') {
    for (var i = 0; i < 50; i++) {
      await _repeatedSubscription(
        owner,
        consumer,
        token,
        '$label repeat $i',
        i,
      );
    }
  }
  final input = _Input();
  final source = StreamController<Reading>();
  owner.readingSource = source;
  final stream = IDataClient(consumer).readings(from: input, cancel: token);
  final done = Completer<void>();
  final sub = stream.listen(
    (_) {},
    onError: (Object _) {},
    onDone: done.complete,
  );
  while (!source.hasListener) {
    await _pump();
  }
  _held.addAll(host.registry.activeStreams);
  switch (ending) {
    case 'complete':
      source.add(Reading(7));
      await source.close();
      await done.future;
    case 'error':
      source.addError(StateError('source failed'));
      await done.future;
    case 'cancel':
      await sub.cancel();
    case 'token':
      token.cancel();
      await done.future;
    case 'paused cancel':
      sub.pause();
      source.add(Reading(7));
      await _pump();
      await sub.cancel();
    case 'withdraw owner':
      if (producer is IRemoteParticipant) {
        await producer.dispose();
      } else {
        producer.dispose();
      }
      await done.future;
    case 'dispose consumer':
      if (consumer is IRemoteParticipant) {
        await consumer.dispose();
      } else {
        consumer.dispose();
      }
      await done.future;
    case 'disconnect':
      await endpoints[1].close();
      await done.future;
  }
  while (source.hasListener) {
    await _pump();
  }
  await source.close();
  owner.readingSource = null;
  for (final guest in guests.reversed) {
    await guest.dispose();
  }
  producer.dispose();
  for (final endpoint in endpoints.reversed) {
    await endpoint.close();
  }
  await observing.cancel();
  _held.addAll(observations);
  _held.addAll([
    host,
    producer,
    consumer,
    stream,
    sub,
    source,
    token,
    ...endpoints,
    ...guests,
  ]);
  _cleanup.add(host.dispose);
  _resources.addAll([
    (name: '$label token', value: token, empty: ['_onCancel']),
    (
      name: '$label registry',
      value: host.registry,
      empty: ['_streamReaders', '_activeStreams', '_pendingStreamEvents'],
    ),
    for (final guest in guests)
      (name: '$label guest', value: guest, empty: ['_data', '_providedData']),
  ]);
  _checks.addAll([
    (name: '$label request', weak: WeakReference(input), collected: true),
    (name: '$label owner', weak: WeakReference(owner), collected: true),
  ]);
}

Future<void> _repeatedSubscription(
  _Owner owner,
  IParticipant consumer,
  CancellationToken token,
  String label,
  int cycle,
) async {
  final started = Completer<void>();
  final source = StreamController<Reading>(onListen: started.complete);
  owner.readingSource = source;
  final input = _Input();
  final stream = IDataClient(consumer).readings(from: input, cancel: token);
  final done = Completer<void>();
  final sub = stream.listen(
    (_) {},
    onError: (Object _) {},
    onDone: done.complete,
  );
  await started.future.timeout(const Duration(seconds: 5));
  switch (cycle % 3) {
    case 0:
      await sub.cancel();
    case 1:
      source.add(Reading(1));
      await source.close();
      await done.future;
    case 2:
      source.addError(StateError('repeated source failure'));
      await done.future;
  }
  while (source.hasListener) {
    await _pump();
  }
  await source.close();
  owner.readingSource = null;
  _held.addAll([stream, sub, source]);
  _checks.add((name: label, weak: WeakReference(input), collected: true));
}

Future<int> _checkResourceTables(_Vm vm, String isolate) async {
  final isolateInfo = await vm.call('getIsolate', {'isolateId': isolate});
  final library = (isolateInfo['rootLib'] as Map)['id'];
  var checked = 0;
  for (var i = 0; i < _resources.length; i++) {
    final ref = await vm.call('evaluate', {
      'isolateId': isolate,
      'targetId': library,
      'expression': '_resources[$i].value',
    });
    final object = await vm.call('getObject', {
      'isolateId': isolate,
      'objectId': ref['id'],
    });
    final fields = (object['fields'] as List).cast<Map<String, dynamic>>();
    for (final name in _resources[i].empty) {
      final field = fields.singleWhere(
        (f) => (f['decl'] as Map)['name'] == name,
      );
      final value = field['value'] as Map;
      final count = await vm.call('evaluate', {
        'isolateId': isolate,
        'targetId': value['id'],
        'expression': 'length',
      });
      if (count['valueAsString'] != '0') {
        throw StateError('${_resources[i].name}.$name: $count');
      }
      checked++;
    }
  }
  return checked;
}

Future<void> _inputPath(
  bool remoteOwner,
  bool remoteConsumer,
  bool bidi,
  String ending,
) async {
  final label =
      'input owner=$remoteOwner consumer=$remoteConsumer bidi=$bidi $ending';
  final host = Host();
  final observations = <StreamEvent>[];
  final observing = host.registry.streamEvents.listen(observations.add);
  final owner = DocumentStore();
  final guests = <IRemoteParticipant>[];
  final endpoints = <RpcPeerEndpoint>[];
  late IParticipant producer;
  if (remoteOwner) {
    final guest = await _join(
      host,
      'producer',
      guests,
      endpoints,
      owns: true,
      words: documentsWords,
    );
    producer = guest;
    await guest.attach([owner]);
    await guest.settle();
  } else {
    producer = host.participant(const Principal('producer'), owners: [owner]);
  }
  final consumer = remoteConsumer
      ? await _join(host, 'consumer', guests, endpoints)
      : host.participant(const Principal('consumer'));
  final client = IDocumentsClient(consumer);
  final payload = _Payload();
  final source = StreamController<int>();
  final input = source.stream.map((v) => '${payload.bytes.length + v}');
  final token = CancellationToken();
  final done = Completer<void>();
  Stream<String>? stream;
  StreamSubscription<String>? subscription;
  Future<int>? result;
  if (bidi) {
    stream = client.preview(input, cancel: token);
    subscription = stream.listen(
      (_) {},
      onError: (Object _) {},
      onDone: done.complete,
    );
  } else {
    result = client.save(input, name: 'notes', cancel: token);
    unawaited(
      result.then(
        (_) => done.complete(),
        onError: (Object _) => done.complete(),
      ),
    );
  }
  while (!source.hasListener) {
    await _pump();
  }
  source.add(1);
  await _pump();
  _held.addAll(host.registry.activeStreams);
  switch (ending) {
    case 'complete':
      unawaited(source.close());
    case 'error':
      source.addError(StateError('input failed'));
    case 'cancel':
      if (subscription != null) {
        await subscription.cancel();
        done.complete();
      } else {
        token.cancel();
      }
    case 'token':
      token.cancel();
  }
  await done.future;
  while (source.hasListener) {
    await _pump();
  }
  await source.close();
  for (final guest in guests.reversed) {
    await guest.dispose();
  }
  producer.dispose();
  for (final endpoint in endpoints.reversed) {
    await endpoint.close();
  }
  await observing.cancel();
  _held.addAll(observations);
  _held.addAll([
    host,
    producer,
    consumer,
    token,
    source,
    ?stream,
    ?subscription,
    ?result,
    ...guests,
    ...endpoints,
  ]);
  _cleanup.add(host.dispose);
  _checks.addAll([
    (
      name: '$label input capture',
      weak: WeakReference(payload),
      collected: true,
    ),
    (name: '$label owner', weak: WeakReference(owner), collected: true),
  ]);
  _resources.addAll([
    (name: '$label token', value: token, empty: ['_onCancel']),
    (
      name: '$label registry',
      value: host.registry,
      empty: ['_streamReaders', '_activeStreams', '_pendingStreamEvents'],
    ),
    for (final guest in guests)
      (name: '$label guest', value: guest, empty: ['_data', '_providedData']),
  ]);
}

Future<void> _exchangeContextRetention(bool cancel) async {
  final payload = _Payload();
  final token = RpcCancellationToken();
  final context = RpcContext.empty().withCancellation(token);
  final input = StreamController<WireJson>();
  final stream = receiveExchange(
    input.stream,
    (_, _) => Stream.value(payload.bytes.length),
    context: context,
  );
  final result = stream.toList();
  final finished = result.then<void>((_) {}, onError: (Object _) {});
  await _pump();
  if (cancel) {
    token.cancel();
  } else {
    input.add(WireJson({'open': <String, Object?>{}}));
  }
  await finished;
  unawaited(input.close());
  _held.addAll([context, stream, input, result]);
  _checks.add((
    name: 'exchange context cancel=$cancel',
    weak: WeakReference(payload),
    collected: true,
  ));
}

Future<void> _sharedSourceRetention(bool cancel) async {
  final payload = _Payload();
  final done = Completer<void>();
  final source = StreamSource<_Payload>(
    source: () => Stream.value(payload),
    onData: (_) {},
    onError: (_, _) {},
    onDone: done.complete,
  );
  if (cancel) {
    source.cancel();
    source.start();
  } else {
    source.start();
    await done.future;
  }
  _held.add(source);
  _checks.add((
    name: 'shared source cancel=$cancel',
    weak: WeakReference(payload),
    collected: true,
  ));
}

Future<void> _sharedRelayRetention() async {
  final payload = _Payload();
  final bridge = StreamBridge<_Payload>(
    source: Stream.fromIterable([payload]),
    onSourceDone: () {
      payload.bytes.first;
    },
    onConsumerCancel: () {
      payload.bytes.first;
    },
  );
  final stream = bridge.stream;
  await stream.drain<void>();
  _held.addAll([bridge, stream]);
  _checks.add((
    name: 'shared neutral relay',
    weak: WeakReference(payload),
    collected: true,
  ));
}

Future<void> main() async {
  final info = await Service.getInfo();
  final uri = info.serverWebSocketUri;
  if (uri == null) throw StateError('run with --enable-vm-service=0');
  final vm = _Vm(await WebSocket.connect('$uri'));
  try {
    final process = await vm.call('getVM');
    final isolate =
        (process['isolates'] as List).cast<Map<String, dynamic>>().singleWhere(
              (i) => i['name'] == 'main',
            )['id']
            as String;
    _controls();
    await _lazy();
    for (final which in ['factory', 'weigher', 'onClosed']) {
      await _closedBridge(which);
    }
    await _cancelledQueue();
    await _wireFactory();
    await _sharedSourceRetention(false);
    await _sharedSourceRetention(true);
    await _sharedRelayRetention();
    await _exchangeContextRetention(false);
    await _exchangeContextRetention(true);
    await _cancelDuringWeigh();
    for (final remoteOwner in [false, true]) {
      for (final remoteConsumer in [false, true]) {
        for (final ending in [
          'complete',
          'error',
          'cancel',
          'token',
          'paused cancel',
          'withdraw owner',
          'dispose consumer',
          if (remoteOwner || remoteConsumer) 'disconnect',
        ]) {
          await _publicPath(remoteOwner, remoteConsumer, ending);
        }
      }
    }
    for (final remoteOwner in [false, true]) {
      for (final remoteConsumer in [false, true]) {
        for (final bidi in [false, true]) {
          for (final ending in ['complete', 'error', 'cancel', 'token']) {
            await _inputPath(remoteOwner, remoteConsumer, bidi, ending);
          }
        }
      }
    }
    for (var i = 0; i < 4; i++) {
      await _pump();
      await vm.call('getAllocationProfile', {'isolateId': isolate, 'gc': true});
    }
    var failed = 0;
    for (final check in _checks) {
      final collected = check.weak.target == null;
      final passed = collected == check.collected;
      if (!passed || !check.name.contains(' repeat ')) {
        stdout.writeln(
          '${passed ? 'PASS' : 'FAIL'} ${check.name}: '
          '${collected ? 'collected' : 'retained'}',
        );
      }
      if (!passed) failed++;
    }
    stdout.writeln(
      '${_checks.length - failed}/${_checks.length} GC checks passed; '
      '${_held.length} stream/subscription/context objects deliberately retained',
    );
    if (failed > 0) exitCode = 1;
    final empty = await _checkResourceTables(vm, isolate);
    stdout.writeln(
      '$empty resource tables empty, including long-lived token callbacks; '
      '200 repeated subscriptions closed',
    );
  } finally {
    for (final cleanup in _cleanup) {
      await cleanup();
    }
    await vm.socket.close();
  }
}
