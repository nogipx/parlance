import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/client.dart';
import 'package:parlance/src/remote/contract.dart';
import 'package:parlance/src/remote/mirror.dart';
import 'package:parlance/src/view/mirror_view.dart';
import 'package:parlance/testing.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/src/participant/local.dart' show Participants;

/// What a newer parlance adds to the language (SPEC §14), met by an older
/// one: a type, an access, a kind of word. A host does not know what its
/// guests speak, so a participant passes over what it does not know; a
/// registry, which must check values, takes no word it cannot check.
final class S<T> implements IStateWord<T> {
  const S(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

enum Mode { a, b }

const when = S<String>('deck.when', PlainShape(TextType()));

/// A host stub speaking the protocol version it is given: enough of the
/// contract to join and follow.
final class _Peer extends ParlanceContractPeer {
  _Peer(this.protocol, super.endpoint);

  final int protocol;

  @override
  Stream<WireFeedItem> onFeed(WireFeedRequest request, {RpcContext? context}) {
    final out = StreamController<WireFeedItem>();
    out.add(
      const WireFeedItem('catalog', {
        'epoch': 'e1',
        'seq': 1,
        'descriptors': <Object?>[],
      }),
    );
    out.add(
      WireFeedItem('snapshot', {
        ...Snapshot(
          epoch: 'e1',
          seq: 1,
          states: const {},
          factsLost: false,
        ).toJson(),
        'subscription': 0,
      }),
    );
    return out.stream;
  }

  @override
  Future<WireDescription> onDescribe(RpcNull r, {RpcContext? context}) async =>
      WireDescription({
        'epoch': 'e1',
        'seq': 1,
        'descriptors': const <Object?>[],
        'protocol': protocol,
        'features': const <String>[],
        'principal': {'kind': 'agent'},
      });

  @override
  Future<WireJson> onSubscribe(WireSubscribe r, {RpcContext? context}) async =>
      const WireJson({'subscription': 1, 'left': <String>[]});

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
  Future<RpcNull> onCancelCall(WireName r, {RpcContext? context}) =>
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

void main() {
  group('a type it does not know', () {
    test('is read as it came, and told on so', () {
      final t = ValueType.fromJson({'type': 'date', 'zone': 'utc'});
      expect(t, isA<UnknownType>());
      expect(t.toJson(), {'type': 'date', 'zone': 'utc'});
      final deep = ValueType.fromJson({
        'type': 'list',
        'item': {'type': 'date'},
      });
      expect(unknownTypeIn(deep)?.json, {'type': 'date'});
      expect(unknownTypeIn(const ListType(TextType())), isNull);
    });

    test('a participant does not stop at a word of it: the code meets '
        'another type than it holds', () {
      final mirror = RegistryMirror()
        ..takeCatalog({
          'descriptors': [
            {
              'is': 'state',
              'name': 'deck.when',
              'type': {'type': 'date'},
            },
          ],
        });
      final view = MirrorView(mirror);
      expect(
        wordStatus(view, when),
        isA<WordMismatch>().having(
          (m) => m.breaks.single,
          'break',
          const WordBreak('type.type', BreakKind.type, 'text', 'date'),
        ),
      );
      expect(wordMismatches(view, const [when]), hasLength(1));
    });

    test('the registry takes no word of it', () {
      final r = Registry();
      final p = r.participant(
        const Principal('deck'),
        vocabularies: [WordSet.open('deck')],
      );
      expect(
        () => p.defineState(
          StateDescriptor(
            'deck.when',
            type: ValueType.fromJson({'type': 'date'}),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'says',
            contains('date is no type this parlance knows'),
          ),
        ),
      );
    });
  });

  test('an access it does not know is denied', () {
    final c = Callers.fromJson({'widlet': 'ask', '*': 'allow'});
    expect(c.rules, {'widlet': Access.deny, '*': Access.allow});
  });

  test('a kind of word it does not know is no word to it', () {
    final mirror = RegistryMirror()
      ..takeCatalog({
        'descriptors': [
          {'is': 'stream', 'name': 'deck.feed'},
        ],
      });
    expect(mirror.descriptorOf('deck.feed'), isNull);
  });

  test('a command whose params, or a variant, are of a type it does not '
      'know is no word to it', () {
    final mirror = RegistryMirror()
      ..takeCatalog({
        'descriptors': [
          {
            'is': 'command',
            'name': 'deck.at',
            'params': {'type': 'date'},
          },
          {
            'is': 'state',
            'name': 'deck.shape',
            'type': {
              'type': 'oneOf',
              'key': 'is',
              'variants': {
                'when': {'type': 'date'},
              },
            },
          },
        ],
      });
    expect(mirror.descriptorOf('deck.at'), isNull);
    expect(mirror.descriptorOf('deck.shape'), isNull);
  });

  test('a host it joins again speaking another protocol is told', () async {
    final hosts = <RpcPeerEndpoint>[];
    addTearDown(() async {
      for (final e in hosts) {
        await e.close();
      }
    });
    var which = 0;
    final connection = RpcClientConnection(
      transportFactory: (_) async {
        which++;
        final (c, s) = RpcChannelTransport.memoryPair();
        final h = RpcPeerEndpoint(transport: s);
        final peer = _Peer(which == 1 ? parlanceProtocol : 99, h);
        h
          ..registerServiceContract(peer)
          ..start();
        hosts.add(h);
        final own = RpcPeerEndpoint(transport: c)..start();
        hosts.add(own);
        return c;
      },
      backoff: const RpcFixedBackoff(Duration(milliseconds: 10)),
    );
    final errors = <ParticipantError>[];
    final p = await RemoteParticipant.join(
      connection,
      onParticipantError: errors.add,
    );
    addTearDown(() async {
      await p.dispose();
      await connection.dispose();
    });
    hosts.first.close(); // the first host goes; it joins again over the next
    for (var i = 0; i < 200 && errors.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(errors.single.code, ParticipantErrorCode.protocol);
    expect(errors.single.op, {'op': 'rejoin'});
  });

  test('a possible break is met only by the word its old name stands for '
      'now', () async {
    final host = TestHost();
    addTearDown(host.dispose);
    final abc = PlainShape(const EnumType(['a', 'b', 'c']));
    final deck = host.participant(
      const Principal('deck'),
      vocabularies: [WordSet.open('deck')],
    );
    final w1 = GeneratedWords(
      deck.raw,
    ).state(S<String>('deck.w1', abc)).define();
    GeneratedWords(deck.raw).state(S<String>('deck.w2', abc)).define();
    host.participant(const Principal('widlet', 'b')).raw.builtAgainst(const [
      S('deck.old', EnumShape(Mode.values)),
    ]);
    final toW1 = host.registry.alias('deck.old', 'deck.w1');
    await pumpEventQueue();
    toW1.dispose();
    host.registry.alias('deck.old', 'deck.w2');
    await pumpEventQueue();
    w1.set('c');
    await pumpEventQueue();
    expect(
      host.registry.mismatches.single.breaks.single.certain,
      isFalse,
      reason: 'w1 is not what deck.old stands for any more',
    );
  });
}
