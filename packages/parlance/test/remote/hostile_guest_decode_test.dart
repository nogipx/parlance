import 'dart:async';

import 'package:parlance/schema.dart';
import 'package:parlance/src/participant/local.dart' show Participants;
import 'package:parlance/src/registry/registry.dart' show Registry;
import 'package:parlance/src/remote/contract.dart';
import 'package:parlance/src/remote/session.dart' show ServeParticipant;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// A frame whose JSON shape the guest controls field by field: its `toJson`
/// is sent verbatim, so a field can carry any type the host's `fromJson`
/// factories do not expect.
final class BadFrame implements IRpcSerializable {
  const BadFrame(this.json);

  factory BadFrame.fromJson(Map<String, dynamic> m) => BadFrame(m);

  final Map<String, dynamic> json;

  @override
  Map<String, dynamic> toJson() => json;
}

/// The hostile guest: calls the host's `Parlance` service with frames of its
/// own shape, bypassing the typed `Wire*` request objects.
final class HostileGuest extends RpcPeerContract {
  // Codec mode even over a zero-copy-capable pair: the hostile frames must
  // arrive as BYTES, or the host never runs its request codec.
  HostileGuest(RpcPeerEndpoint endpoint)
    : super(
        ParlanceContractNames.service,
        endpoint,
        callerDataTransferMode: RpcDataTransferMode.codec,
      );

  static const _codec = RpcCodec<BadFrame>(BadFrame.fromJson);

  @override
  void setup() {}

  /// The host's answer to [params] sent to [method], or the error it gives.
  Future<WireJson> unary(String method, Map<String, dynamic> params) =>
      callUnary<BadFrame, WireJson>(
        methodName: method,
        requestCodec: _codec,
        responseCodec: ParlanceContractCodecs.codecWireJson,
        request: BadFrame(params),
      );

  /// The host's answer to [params] sent to a server-streaming [method].
  Stream<WireJson> stream(String method, Map<String, dynamic> params) =>
      callServerStream<BadFrame, WireJson>(
        methodName: method,
        requestCodec: _codec,
        responseCodec: ParlanceContractCodecs.codecWireJson,
        request: BadFrame(params),
      );
}

void main() {
  test('a badly-typed frame is refused as the guest\'s fault, the session '
      'unharmed', () async {
    final opened = <RpcPeerEndpoint>[];
    addTearDown(() async {
      for (final e in opened) {
        await e.close();
      }
    });
    final (g, h) = RpcChannelTransport.memoryPair();
    final hostEp = RpcPeerEndpoint(transport: h);
    final registry = Registry();
    final session = registry.participant(const Principal('guest', 'g')).serve(
      hostEp,
    );
    hostEp.start();
    final guestEp = RpcPeerEndpoint(transport: g)..start();
    opened.addAll([hostEp, guestEp]);
    final guest = HostileGuest(guestEp);
    final caller = ParlanceContractPeerCaller(guestEp);

    // Control: a well-formed frame is served.
    final desc = await caller.describe(RpcNull());
    expect(desc.json['protocol'], parlanceProtocol);
    // Paired control: a well-formed call frame is NOT refused — it reaches
    // the session and is answered.
    final ok = await guest.unary(ParlanceContractNames.invoke, {
      'id': 'k1',
      'command': 'no.such',
      'params': <String, Object?>{},
    });
    expect(ok.json['result'], isNotNull);

    var dead = false;
    unawaited(session.ended.then((_) => dead = true));

    // Each entry: the frame, and the field the refusal must name.
    final cases = <String, (String, Map<String, dynamic>, String)>{
      'call, id a number': (
        ParlanceContractNames.invoke,
        {'id': 1, 'command': 'x', 'params': <String, Object?>{}},
        'id',
      ),
      'why, state a number': (
        ParlanceContractNames.why,
        {'state': 7},
        'state',
      ),
      'recent, count text': (
        ParlanceContractNames.recent,
        {'fact': 'f', 'count': 'many'},
        'count',
      ),
      'subscribe, states mixed': (
        ParlanceContractNames.subscribe,
        {'states': <Object?>['a', 7]},
        'states',
      ),
      'set, state a number': (
        ParlanceContractNames.write,
        {'state': 7, 'value': 1},
        'state',
      ),
      'emit, fact a number': (
        ParlanceContractNames.emit,
        {'fact': 7, 'payload': 1},
        'fact',
      ),
      'undefine, name a number': (
        ParlanceContractNames.undefine,
        {'name': 7},
        'name',
      ),
      'cancel, name a number': (
        ParlanceContractNames.cancelCall,
        {'name': 7},
        'name',
      ),
      'define, descriptor text': (
        ParlanceContractNames.define,
        {'descriptor': 'junk'},
        'descriptor',
      ),
      'feed, since text': (
        ParlanceContractNames.feed,
        {'since': 'later'},
        'since',
      ),
    };

    for (final entry in cases.entries) {
      final (method, params, field) = entry.value;
      Object? outcome;
      if (method == ParlanceContractNames.feed) {
        try {
          await guest.stream(method, params).first;
        } catch (e) {
          outcome = e;
        }
      } else {
        try {
          await guest.unary(method, params);
        } catch (e) {
          outcome = e;
        }
      }
      expect(outcome, isA<RpcStatusException>(), reason: entry.key);
      final refusal = outcome! as RpcStatusException;
      expect(refusal.statusCode, RpcStatus.invalidArgument, reason: entry.key);
      expect(refusal.message, contains('"$field"'), reason: entry.key);
      // The connection and the session survive every bad frame.
      expect(dead, isFalse, reason: entry.key);
      await caller.describe(RpcNull());
    }

    // Ablation: a semantically bad op through `apply` is still refused the
    // way it always was, per-op.
    final apply = await caller.apply(const WireJson({
      'ops': <Object?>[
        {'op': 'set', 'state': 'no.such', 'value': 1},
      ],
    }));
    expect((apply.json['results']! as List).single, isNotEmpty);
  });
}
