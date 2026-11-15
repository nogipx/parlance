import 'package:parlance/tools.dart';
import 'package:parlance/src/participant/local.dart' show Participants;
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/src/remote/client.dart';
import 'package:parlance/src/remote/contract.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

const _user = Principal('user');
const _owner = Principal('house');

final class _NoDiagnosticsHost extends ParlanceContractPeer {
  _NoDiagnosticsHost(super.endpoint);

  int requests = 0;

  @override
  Future<WireDescription> onDescribe(RpcNull r, {RpcContext? context}) async =>
      WireDescription({
        'protocol': parlanceProtocol,
        'features': [
          for (final f in parlanceFeatures)
            if (f != 'causalDiagnostics') f,
        ],
      });

  @override
  Future<WireJson> onWhy(WireWhyRequest r, {RpcContext? context}) async {
    requests++;
    fail('client must check causalDiagnostics before sending why');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Registry registry;
  late RawStateWriter state;
  final peers = <RpcPeerEndpoint>[];

  setUp(() {
    registry = Registry();
    state = registry.defineState(
      StateDescriptor('house.value', type: const IntType()),
      by: _owner,
    );
    registry.defineCommand(
      CommandDescriptor('house.run', callers: Callers.anyone),
      (c) => state.set(1, cause: c.causeFor(_owner)),
    );
  });
  tearDown(() async {
    for (final peer in peers.reversed) {
      await peer.close();
    }
    peers.clear();
    await registry.dispose();
  });

  RpcPeerEndpoint serve({Set<String>? features}) {
    final (a, b) = RpcChannelTransport.pair();
    final host = RpcPeerEndpoint(transport: a);
    registry.participant(_user).serve(host, features: features);
    host.start();
    final client = RpcPeerEndpoint(transport: b)..start();
    peers.addAll([host, client]);
    return client;
  }

  test('client requires causalDiagnostics for every why operation', () async {
    final (a, b) = RpcChannelTransport.pair();
    final endpoint = RpcPeerEndpoint(transport: a);
    final host = _NoDiagnosticsHost(endpoint);
    endpoint
      ..registerServiceContract(host)
      ..start();
    final own = RpcPeerEndpoint(transport: b)..start();
    peers.addAll([endpoint, own]);
    final client = ParlanceClient(own);
    await expectLater(
      client.explain('house.value', historyCount: 10),
      throwsUnsupportedError,
    );
    await expectLater(client.inspectCall('root'), throwsUnsupportedError);
    expect(host.requests, 0);
  });

  test('client reads journal metadata and requested history', () async {
    final client = ParlanceClient(serve());
    await registry.call('house.run', {}, by: _user, id: 'root');
    final explanation = await client.explain('house.value', historyCount: 1);
    final end = explanation.trail.single as JournalEnd;
    expect(end.id, 'root');
    expect(end.epoch, registry.epoch);
    expect(end.payloads, isTrue);
    expect(explanation.history, hasLength(1));
    final inspection = await client.inspectCall('root');
    expect((inspection['message'] as Map)['kind'], 'end');
  });

  test('why returns the full mixed trail without format negotiation', () async {
    final caller = ParlanceContractPeerCaller(serve());
    final changed = registry.defineFact(
      FactDescriptor('house.changed', type: const IntType()),
      by: _owner,
    );
    changed.say(1, id: 'fact');
    final fact = registry.recent('house.changed', 1).single;
    await registry.call(
      'house.run',
      {},
      by: _user,
      id: 'root',
      cause: fact.cause.child(fact.id, by: _user, word: fact.fact),
    );
    final response = (await caller.why(
      const WireWhyRequest(state: 'house.value'),
    )).json;
    final explanation = Explanation.fromJson(response);
    expect(explanation.trail.map((e) => e.kind), ['end', 'fact']);
    expect(explanation.trail.map((e) => e.epoch), everyElement(registry.epoch));
    expect(explanation.trailCut, isFalse);
    expect(explanation.gap, isNull);
  });

  test('why preserves hidden call payloads over RPC', () async {
    registry.defineCommand(
      CommandDescriptor(
        'house.private',
        callers: Callers.only(['house']),
        params: const RecordType({'secret': Field(TextType())}),
        returns: const TextType(),
      ),
      (c) {
        state.set(1, cause: c.causeFor(_owner));
        return 'private result';
      },
    );
    expect(
      await registry.call(
        'house.private',
        {'secret': 'private input'},
        by: _owner,
        id: 'hidden',
      ),
      isA<CallDone<Object?>>().having(
        (r) => r.value,
        'value',
        'private result',
      ),
    );
    final endpoint = serve();
    final response = (await ParlanceContractPeerCaller(
      endpoint,
    ).why(const WireWhyRequest(state: 'house.value'))).json;
    final entry = (response['trail'] as List).single as Map;
    expect(entry['kind'], 'end');
    expect(entry['payloads'], isFalse);
    expect(entry, isNot(contains('params')));
    expect(entry['result'], {'done': true});
    final explanation = await ParlanceClient(endpoint).explain('house.value');
    final end = explanation.trail.single as JournalEnd;
    expect(end.id, 'hidden');
    expect(end.payloads, isFalse);
    expect(end.epoch, registry.epoch);
  });

  test('host refuses why when causalDiagnostics is disabled', () async {
    final caller = ParlanceContractPeerCaller(
      serve(features: {...parlanceFeatures}..remove('causalDiagnostics')),
    );
    for (final request in [
      const WireWhyRequest(state: 'house.value'),
      const WireWhyRequest(call: 'root'),
    ]) {
      await expectLater(
        caller.why(request),
        throwsA(
          isA<RpcStatusException>().having(
            (e) => e.statusCode,
            'status',
            RpcStatus.unimplemented,
          ),
        ),
      );
    }
  });

  test('explanations reject bare CallRecord trails', () async {
    await registry.call('house.run', {}, by: _user, id: 'root');
    final explanation = registry.explain('house.value');
    final end = explanation.trail.single as JournalEnd;
    expect(
      () => Explanation.fromJson({
        ...explanation.toJson(),
        'trail': [end.call.toJson()],
      }),
      throwsA(isA<TypeError>()),
    );
  });
}
