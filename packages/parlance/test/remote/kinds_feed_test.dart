import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/client.dart';
import 'package:parlance/src/remote/contract.dart';
import 'package:parlance/src/remote/mirror.dart' show RegistryMirror;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// Entities change often (a room added, a visitor come); the catalog
/// around them does not. A feed whose client speaks `kinds` (SPEC §14)
/// tells the one kind that changed, not the whole catalog again; a
/// client or a host of before it gets and sends the whole catalog.
void main() {
  late Registry r;
  late LocalParticipant house;
  late List<Choice> rooms;
  final opened = <RpcPeerEndpoint>[];
  setUp(() {
    r = Registry();
    house = r.participant(
      const Principal('house'),
      vocabularies: [WordSet.open('house')],
    );
    rooms = [const Choice('main')];
    house.addChoices(Choices('room', list: () => rooms));
    house.defineCommand(
      CommandDescriptor(
        'house.show',
        params: const RecordType({'room': Field(ChoiceType('room'))}),
        callers: Callers.only(['agent']),
      ),
      (_) {},
      whyNot: () => rooms.length > 1 ? null : 'only one room',
    );
  });
  tearDown(() async {
    for (final e in opened) {
      await e.close();
    }
    opened.clear();
    await r.dispose();
  });

  RpcPeerEndpoint serve({Set<String>? features}) {
    final (g, h) = RpcChannelTransport.memoryPair();
    final host = RpcPeerEndpoint(transport: h);
    r.participant(const Principal('agent')).serve(host, features: features);
    host.start();
    final own = RpcPeerEndpoint(transport: g)..start();
    opened.addAll([host, own]);
    return own;
  }

  /// The kinds of the feed's items, read until [until] says enough.
  Future<List<WireFeedItem>> items(
    Stream<WireFeedItem> feed,
    bool Function(List<WireFeedItem>) until,
  ) async {
    final got = <WireFeedItem>[];
    await for (final i in feed) {
      got.add(i);
      if (until(got)) break;
    }
    return got;
  }

  test('a client that speaks kinds is told the kind that changed, and '
      'what can run since', () async {
    final caller = ParlanceContractPeerCaller(serve());
    final feed = caller.feed(const WireFeedRequest(features: {'kinds'}));
    final first = items(feed, (g) => g.any((i) => i.kind == 'unavailable'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    rooms = [...rooms, const Choice('break')];
    house.choicesChanged('room');
    final got = await first.timeout(const Duration(seconds: 2));
    final after = got.skipWhile((i) => i.kind != 'kind').toList();
    expect([for (final i in after) i.kind], ['kind', 'unavailable']);
    expect(after.first.json, {
      'name': 'room',
      'kind': Choices('room', list: () => rooms).toJson(),
    });
    expect(after.last.json['unavailable'], isEmpty);
    expect(
      [for (final i in got) i.kind].where((k) => k == 'catalog'),
      hasLength(1),
      reason: 'the first one only',
    );
  });

  for (final (who, request, features) in [
    ('a client of before kinds', const WireFeedRequest(), null),
    (
      'a host of before kinds',
      const WireFeedRequest(features: {'kinds'}),
      {'built'},
    ),
  ]) {
    test('$who: the whole catalog', () async {
      final caller = ParlanceContractPeerCaller(serve(features: features));
      final feed = caller.feed(request);
      final got = items(
        feed,
        (g) => g.where((i) => i.kind == 'catalog').length == 2,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      rooms = [...rooms, const Choice('break')];
      house.choicesChanged('room');
      final all = await got.timeout(const Duration(seconds: 2));
      expect(all.where((i) => i.kind == 'kind'), isEmpty);
      expect(
        ((all.last.json['kinds'] as List).single as Map)['entities'],
        hasLength(2),
      );
    });
  }

  test('a mirror keeps the catalog whole: the kind that changed in its '
      'place, one that went gone', () async {
    final mirror = RegistryMirror()..follow(ParlanceClient(serve()));
    addTearDown(mirror.dispose);
    await mirror.changes.firstWhere((_) => mirror.synced);
    final descriptors = mirror.catalog['descriptors'];
    final told = mirror.catalogChanges.first;
    rooms = [...rooms, const Choice('break')];
    house.choicesChanged('room');
    await told;
    expect(
      [
        for (final e
            in ((mirror.catalog['kinds'] as List).single as Map)['entities']
                as List)
          (e as Map)['id'],
      ],
      ['main', 'break'],
    );
    expect(mirror.catalog['descriptors'], same(descriptors));
    await mirror.statusChanges
        .firstWhere((_) => mirror.statusOf('house.show') is WordReady)
        .timeout(const Duration(seconds: 2));

    final gone = mirror.catalogChanges.first;
    final kind = r
        .participant(
          const Principal('deck'),
          vocabularies: [WordSet.open('deck')],
        )
        .addChoices(Choices('deck', list: () => const []));
    await gone;
    expect(mirror.catalog['kinds'], hasLength(2));
    final went = mirror.catalogChanges.first;
    kind.dispose();
    await went;
    expect(
      [for (final k in mirror.catalog['kinds'] as List) (k as Map)['name']],
      ['room'],
    );
  });
}
