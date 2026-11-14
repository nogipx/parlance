/// Streaming throughput controls for the VM and dart2js/node.
///
/// Compile with `fvm dart compile exe benchmark/streams_bench.dart -o /tmp/streams`
/// or `fvm dart compile js -O2 benchmark/streams_bench.dart -o /tmp/streams.js`.
/// Run JS with `node benchmark/run_streams.js /tmp/streams.js`.
/// `--count=`, `--rounds=`, `--bytes=` and `--only=LL` tune the workload.
/// LL/LR/RL/RR name the owner then reader placement. Results are median us/item;
/// setup and teardown are excluded, and every case verifies its received count.
library;

import 'dart:convert';

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
import 'package:rpc_dart/rpc_dart.dart';

const _params = RecordShape<()>({}, to: _to, from: _from, get: _get);
const _any = PlainShape(AnyType());
Map<String, Object?> _to(() value) => {};
() _from(Map<String, Object?> value) => ();
Object? _get(() value, int index) => null;

class _Value implements IRpcSerializable {
  _Value(this.value);
  final Object? value;
  @override
  Map<String, dynamic> toJson() => {'value': value};
  static final codec = RpcCodec<_Value>((m) => _Value(m['value']));
}

class _Native extends RpcResponderContract {
  _Native(this.values) : super('Bench');
  final Stream<Object?> Function() values;
  @override
  void setup() {
    addServerStreamMethod<RpcNull, _Value>(
      methodName: 'server',
      requestCodec: RpcNull.codec,
      responseCodec: _Value.codec,
      handler: (_, {context}) => values().map(_Value.new),
    );
    addClientStreamMethod<_Value, RpcInt>(
      methodName: 'client',
      requestCodec: _Value.codec,
      responseCodec: RpcInt.codec,
      handler: (input, {context}) async => RpcInt(await input.length),
    );
    addBidirectionalMethod<_Value, _Value>(
      methodName: 'bidi',
      requestCodec: _Value.codec,
      responseCodec: _Value.codec,
      handler: (input, {context}) => input,
    );
  }
}

class _Caller extends RpcCallerContract {
  _Caller(RpcCallerEndpoint endpoint) : super('Bench', endpoint);
  Stream<_Value> server() => callServerStream<RpcNull, _Value>(
    methodName: 'server',
    request: const RpcNull(),
    requestCodec: RpcNull.codec,
    responseCodec: _Value.codec,
  );
  Future<RpcInt> client(Stream<Object?> input) =>
      callClientStream<_Value, RpcInt>(
        methodName: 'client',
        requests: input.map(_Value.new),
        requestCodec: _Value.codec,
        responseCodec: RpcInt.codec,
      );
  Stream<_Value> bidi(Stream<Object?> input) =>
      callBidirectionalStream<_Value, _Value>(
        methodName: 'bidi',
        requests: input.map(_Value.new),
        requestCodec: _Value.codec,
        responseCodec: _Value.codec,
      );
}

Future<void> main(List<String> args) async {
  int option(String name, int fallback) {
    for (final arg in args) {
      if (arg.startsWith('--$name=')) return int.parse(arg.split('=').last);
    }
    return fallback;
  }

  final count = option('count', 3000);
  final rounds = option('rounds', 7);
  final bytes = option('bytes', 0);
  final only = args
      .where((arg) => arg.startsWith('--only='))
      .firstOrNull
      ?.substring(7);
  final suffix = 'x' * bytes;
  Stream<Object?> values() => Stream.fromIterable(
    Iterable.generate(count, (i) => bytes == 0 ? i : '$i:$suffix'),
  );
  final cases = <String, Future<int> Function()>{'dart': () => values().length};
  final cleanup = <Future<void> Function()>[];
  final (a, b) = RpcChannelTransport.pair();
  final nativeServer = RpcResponderEndpoint(transport: b)
    ..registerServiceContract(_Native(values))
    ..start();
  final nativeClient = RpcCallerEndpoint(transport: a);
  final native = _Caller(nativeClient);
  cases['rpc.server'] = () => native.server().length;
  cases['rpc.client'] = () async => (await native.client(values())).value;
  cases['rpc.bidi'] = () => native.bidi(values()).length;
  cleanup.addAll([nativeClient.close, nativeServer.close]);

  for (final remoteOwner in [false, true]) {
    for (final remoteReader in [false, true]) {
      final host = Host();
      final peers = <RpcPeerEndpoint>[];
      final guests = <IRemoteParticipant>[];
      Future<IParticipant> participant(String name, bool remote) async {
        if (!remote) {
          return host.participant(
            Principal(name),
            vocabularies: name == 'source' ? [const WordSet.open('bench')] : [],
          );
        }
        final (x, y) = RpcChannelTransport.pair();
        final server = RpcPeerEndpoint(transport: x);
        host.serve(
          Principal(name),
          server,
          vocabularies: name == 'source' ? [const WordSet.open('bench')] : [],
        );
        server.start();
        final peer = RpcPeerEndpoint(transport: y)..start();
        peers.addAll([server, peer]);
        final guest = await Host.joinEndpoint(peer);
        guests.add(guest);
        return guest;
      }

      final owner = await participant('source', remoteOwner);
      final reader = await participant('reader', remoteReader);
      owner.raw.defineStream(
        ServerStreamDescriptor('bench.server', type: const AnyType()),
        (_) => values(),
      );
      owner.raw.defineStream(
        ClientStreamDescriptor(
          'bench.client',
          input: const AnyType(),
          type: const IntType(),
          callers: Callers.anyone,
        ),
        (call) => Stream.fromFuture(call.input!.length),
      );
      owner.raw.defineStream(
        BidiStreamDescriptor(
          'bench.bidi',
          input: const AnyType(),
          type: const AnyType(),
          callers: Callers.anyone,
        ),
        (call) => call.input!,
      );
      await owner.settle();
      final label = '${remoteOwner ? 'R' : 'L'}${remoteReader ? 'R' : 'L'}';
      cases['$label.server'] = () =>
          reader.raw.openStream('bench.server', (), _params, _any).length;
      cases['$label.client'] = () async => (await reader.raw
          .openStream(
            'bench.client',
            (),
            _params,
            const PlainShape(IntType()),
            kind: 'clientStream',
            input: values(),
            inputShape: _any,
          )
          .single);
      cases['$label.bidi'] = () => reader.raw
          .openStream(
            'bench.bidi',
            (),
            _params,
            _any,
            kind: 'bidiStream',
            input: values(),
            inputShape: _any,
          )
          .length;
      cleanup.add(() async {
        for (final guest in guests.reversed) {
          await guest.dispose();
        }
        for (final peer in peers.reversed) {
          await peer.close();
        }
        await host.dispose();
      });
    }
  }

  try {
    final samples = <String, List<double>>{
      for (final name in cases.keys) name: [],
    };
    final entries = cases.entries
        .where((entry) => only == null || entry.key.startsWith(only))
        .toList();
    if (entries.isEmpty) {
      throw ArgumentError('no benchmark cases matched $only');
    }
    for (var round = -3; round < rounds; round++) {
      // Rotate execution order to reduce bias from warmup and thermal drift.
      for (var j = 0; j < entries.length; j++) {
        final entry = entries[(j + round + 3) % entries.length];
        final watch = Stopwatch()..start();
        final received = await entry.value();
        watch.stop();
        if (received != count) {
          throw StateError('${entry.key}: $received != $count');
        }
        if (round >= 0) {
          samples[entry.key]!.add(watch.elapsedMicroseconds / count);
        }
      }
    }
    print(
      jsonEncode({
        'count': count,
        'bytes': bytes,
        'rounds': rounds,
        'microsPerItem': {
          for (final entry in samples.entries.where(
            (entry) => entry.value.isNotEmpty,
          ))
            entry.key: (entry.value..sort())[entry.value.length ~/ 2],
        },
      }),
    );
  } finally {
    for (final close in cleanup.reversed) {
      await close();
    }
  }
}
