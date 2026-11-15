import 'package:parlance/tools.dart';
import 'package:parlance/src/participant/local.dart' show Participants;
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/src/remote/client.dart';
import 'package:parlance/src/remote/contract.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

const _user = Principal('user');
const _owner = Principal('house');
const _legacyResponse = {
  'state': 'house.value',
  'value': 1,
  'trail': [
    {
      'id': 'root',
      'command': 'house.run',
      'params': {'value': 1},
      'cause': {
        'by': {'kind': 'user'},
      },
      'result': {'done': true, 'value': null},
      'started': '2026-01-01T00:00:00.000Z',
      'finished': '2026-01-01T00:00:01.000Z',
    },
  ],
};

// Implements the original describe/why wire behavior, including a bare
// CallRecord trail. Other operations are deliberately unavailable.
final class _LegacyHost extends ParlanceContractPeer {
  _LegacyHost(super.endpoint);

  WireWhyRequest? request;

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
    request = r;
    return const WireJson(_legacyResponse);
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

  test('new client reads an original why response over RPC', () async {
    final (a, b) = RpcChannelTransport.pair();
    final endpoint = RpcPeerEndpoint(transport: a);
    final host = _LegacyHost(endpoint);
    endpoint
      ..registerServiceContract(host)
      ..start();
    final own = RpcPeerEndpoint(transport: b)..start();
    peers.addAll([endpoint, own]);
    final client = ParlanceClient(own);
    final explanation = await client.explain('house.value', historyCount: 10);
    final end = explanation.trail.single as JournalEnd;
    expect(end.call.id, 'root');
    expect(end.call.params, {'value': 1});
    expect(end.call.result, isA<CallDone<Object?>>());
    expect(end.epoch, isEmpty, reason: 'legacy replies have no journal epoch');
    expect(host.request!.state, 'house.value');
    expect(host.request!.features, isNull);
    expect(host.request!.historyCount, 0);
    host.request = null;
    await expectLater(client.inspectCall('root'), throwsUnsupportedError);
    expect(
      host.request,
      isNull,
      reason: 'no new operation sent to an old host',
    );
  });

  for (final hostDiagnostics in [false, true]) {
    test(
      'new client negotiates journal trails, host=$hostDiagnostics',
      () async {
        final client = ParlanceClient(
          serve(
            features: {
              for (final f in parlanceFeatures)
                if (hostDiagnostics || f != 'causalDiagnostics') f,
            },
          ),
        );
        await registry.call('house.run', {}, by: _user, id: 'root');
        final explanation = await client.explain(
          'house.value',
          historyCount: 1,
        );
        final end = explanation.trail.single as JournalEnd;
        expect(end.id, 'root');
        expect(end.epoch, hostDiagnostics ? registry.epoch : '');
        expect(explanation.history, hasLength(hostDiagnostics ? 1 : 0));
      },
    );
  }

  test('old client reads bare CallRecords from a new host', () async {
    final caller = ParlanceContractPeerCaller(serve());
    await registry.call('house.run', {}, by: _user, id: 'root');
    final response = (await caller.why(
      const WireWhyRequest(state: 'house.value'),
    )).json;
    final trail = response['trail'] as List;
    final call = CallRecord.fromJson(trail.single);
    expect(call.id, 'root');
    expect((trail.single as Map), isNot(contains('kind')));
    expect(response['trailCut'], isNot(isTrue));
  });

  test('old client gets an explicit gap at an unsupported ancestor', () async {
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
    final trail = response['trail'] as List;
    expect(CallRecord.fromJson(trail.single).id, 'root');
    expect(response['trailCut'], isTrue);
    expect(response['gap'], contains('causalDiagnostics'));
    final full = await ParlanceClient(caller.endpoint).explain('house.value');
    expect(full.trail.map((e) => e.kind), ['end', 'fact']);
    expect(full.trailCut, isFalse);
  });

  test('mixed trails require both the host and the request feature', () async {
    final caller = ParlanceContractPeerCaller(
      serve(features: {...parlanceFeatures}..remove('causalDiagnostics')),
    );
    await registry.call('house.run', {}, by: _user, id: 'root');
    final response = (await caller.why(
      const WireWhyRequest(
        state: 'house.value',
        features: {'causalDiagnostics'},
      ),
    )).json;
    expect(CallRecord.fromJson((response['trail'] as List).single).id, 'root');
  });
}
