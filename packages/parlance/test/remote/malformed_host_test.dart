import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/client.dart';
import 'package:parlance/src/remote/contract.dart';
import 'package:parlance/src/remote/mirror.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// A host with a defect sends what is no item of the protocol (SPEC §14):
/// a tick whose seq is text, a catalog of junk. The copy does not stop
/// at it, nor follow it for ever: it follows again from a snapshot and
/// says so, and stops when the host keeps sending it.
final class _Host extends ParlanceContractPeer {
  _Host(super.endpoint, this.items);

  /// What the feed asked for the [n]th time sends, and then stays open.
  final List<WireFeedItem> Function(int n) items;
  int feeds = 0;

  @override
  Stream<WireFeedItem> onFeed(WireFeedRequest request, {RpcContext? context}) {
    final out = StreamController<WireFeedItem>();
    for (final i in items(feeds++)) {
      out.add(i);
    }
    return out.stream;
  }

  @override
  Future<WireDescription> onDescribe(RpcNull r, {RpcContext? context}) async =>
      WireDescription({
        ..._catalog,
        'protocol': parlanceProtocol,
        'features': const <String>[],
        'principal': {'kind': 'agent'},
      });

  @override
  Future<WireJson> onSubscribe(WireSubscribe r, {RpcContext? context}) async =>
      WireJson({'subscription': 1, 'left': const <String>[]});

  @override
  Future<WireCallReply> onInvoke(WireCallRequest r, {RpcContext? context}) =>
      throw UnimplementedError();
  @override
  Future<WireJson> onWhy(WireWhyRequest r, {RpcContext? context}) =>
      throw UnimplementedError();
  @override
  Future<WireJson> onRecent(WireRecentRequest r, {RpcContext? context}) =>
      throw UnimplementedError();
  @override
  Future<RpcNull> onDefine(WireDefine r, {RpcContext? context}) =>
      throw UnimplementedError();
  @override
  Future<RpcNull> onUndefine(WireName r, {RpcContext? context}) =>
      throw UnimplementedError();
  @override
  Future<RpcNull> onWrite(WireSet r, {RpcContext? context}) =>
      throw UnimplementedError();
  @override
  Future<WireTaken> onEmit(WireEmit r, {RpcContext? context}) =>
      throw UnimplementedError();
  @override
  Future<WireJson> onApply(WireJson r, {RpcContext? context}) =>
      throw UnimplementedError();
}

const _catalog = {
  'epoch': 'e1',
  'seq': 1,
  'descriptors': [
    {
      'is': 'state',
      'name': 'deck.v',
      'type': {'type': 'int'},
    },
  ],
};

WireFeedItem catalog() => const WireFeedItem('catalog', _catalog);

WireFeedItem snapshot(int v) => WireFeedItem('snapshot', {
  ...Snapshot(
    epoch: 'e1',
    seq: 1,
    states: {
      'deck.v': {null: v},
    },
    factsLost: false,
  ).toJson(),
  'subscription': 0,
});

const badTick = WireFeedItem('tick', {'epoch': 'e1', 'from': 'two'});

void main() {
  final opened = <RpcPeerEndpoint>[];
  tearDown(() async {
    for (final e in opened) {
      await e.close();
    }
    opened.clear();
  });

  (RpcPeerEndpoint, _Host) serve(List<WireFeedItem> Function(int n) items) {
    final (g, h) = RpcChannelTransport.memoryPair();
    final endpoint = RpcPeerEndpoint(transport: h);
    final host = _Host(endpoint, items);
    endpoint
      ..registerServiceContract(host)
      ..start();
    final own = RpcPeerEndpoint(transport: g)..start();
    opened.addAll([endpoint, own]);
    return (own, host);
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'an item it cannot read: told, and followed again from a snapshot',
    () async {
      final (own, host) = serve(
        (n) => n == 0
            ? [catalog(), snapshot(1), badTick]
            : [catalog(), snapshot(2)],
      );
      final told = <(Object, bool)>[];
      final mirror = RegistryMirror()
        ..onMalformed = (e, {required gaveUp}) {
          told.add((e, gaveUp));
        }
        ..follow(ParlanceClient(own));
      addTearDown(mirror.dispose);
      await until(() => mirror.read('deck.v') == 2);
      expect(mirror.read('deck.v'), 2);
      expect(mirror.synced, isTrue);
      expect(host.feeds, 2);
      expect(told.single.$2, isFalse);
      expect('${told.single.$1}', contains('tick'));
    },
  );

  test('a catalog of junk keeps the one it had', () async {
    final (own, host) = serve(
      (n) => n == 0
          ? [
              catalog(),
              snapshot(1),
              const WireFeedItem('catalog', {'descriptors': 'all of them'}),
            ]
          : [catalog(), snapshot(1)],
    );
    final told = <Object>[];
    final mirror = RegistryMirror()
      ..onMalformed = (e, {required gaveUp}) {
        told.add(e);
      }
      ..follow(ParlanceClient(own));
    addTearDown(mirror.dispose);
    await until(() => host.feeds == 2 && mirror.synced);
    expect('${told.single}', contains('catalog'));
    expect(mirror.statusOf('deck.v'), isA<WordReady>());
  });

  test('a host that keeps sending it is not followed for ever', () async {
    final (own, host) = serve((_) => [catalog(), snapshot(1), badTick]);
    final told = <bool>[];
    final mirror = RegistryMirror()
      ..onMalformed = (e, {required gaveUp}) {
        told.add(gaveUp);
      }
      ..follow(ParlanceClient(own));
    addTearDown(mirror.dispose);
    await until(() => told.contains(true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(told, [false, false, false, true]);
    expect(host.feeds, RegistryMirror.malformedLimit + 1);
    expect(mirror.synced, isFalse);
  });

  test('a participant tells it as its error', () async {
    final (own, _) = serve(
      (n) =>
          n == 0 ? [catalog(), snapshot(1), badTick] : [catalog(), snapshot(2)],
    );
    final p = await RemoteParticipant.joinEndpoint(own);
    addTearDown(p.close);
    final errors = <ParticipantError>[];
    p.errors.listen(errors.add);
    await until(() => errors.isNotEmpty);
    expect(errors.single.code, ParticipantErrorCode.malformed);
    expect(errors.single.op, {'op': 'feed'});
  });
}
