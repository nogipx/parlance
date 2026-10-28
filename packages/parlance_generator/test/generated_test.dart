import 'dart:convert';
import 'dart:io';

import 'package:parlance/schema.dart';
import 'package:test/test.dart';

import 'fixtures/player.dart';

const me = Principal('player');
const ann = Principal('listener', 'ann');
const anyone = Callers({'*': Access.allow});

/// A player's owner: only its handlers and what it has now.
final class Deck extends PlayerOwner {
  final List<Track> library = [
    const Track(title: 'A'),
    const Track(title: 'B'),
  ];
  Track? loaded;
  int level = 50;
  int stopped = 0;

  @override
  void sync() {
    volume.set(level);
    repeat.set(Repeat.off);
    playing.set(loaded);
  }

  @override
  void setVolume(CommandCallOf<PlayerSetVolume> call) {
    level = call.params.volume;
    volume.set(level, cause: call.inReply);
    if (level > 90) {
      clipped(volume: level, cause: call.inReply);
    }
  }

  @override
  Future<void> play(CommandCallOf<PlayerPlay> call) async {
    playing.set(call.params.track, cause: call.inReply);
  }

  @override
  String? whyNotPlay() => library.isEmpty ? 'nothing to play' : null;

  @override
  int skip(CommandCallOf<PlayerSkip> call) => call.params.count;

  @override
  void stop(CommandCallOf<()> call) => stopped++;

  @override
  List<Track> search(QueryAsk<PlayerSearch> ask) => [
    for (final t in library)
      if (t.title.contains(ask.params.text)) t,
  ];
}

/// The words made from `fixtures/player.dart` work as words written by
/// hand: the registry takes them, checks them, and carries their values.
void main() {
  late Registry r;
  late IParticipant p;
  late IParticipant asAnn;
  late IParticipant asBob;
  setUp(() {
    r = Registry(onError: (e, st) => throw e);
    asAnn = r.participant(ann);
    asBob = r.participant(const Principal('guest', 'bob'));
    p = r.participant(
      me,
      vocabularies: [playerWords],
      access: const WordAccess(call: anyone),
    );
  });
  tearDown(() => r.dispose());

  test('states carry their values, a class through its toJson', () {
    final playing = p.state(PlayerState.playing).define();
    const track = Track(title: 'Song', seconds: 200, artist: Artist('Ann'));
    playing.set(track);
    expect(asAnn.read('player.playing'), {
      'title': 'Song',
      'length': 200,
      'artist': {'name': 'Ann'},
    });
    expect(asAnn.state(PlayerState.playing).read()!.artist!.name, 'Ann');
    final volume = p.state(PlayerState.volume).define();
    expect(() => volume.set(150), throwsA(isA<TypeMismatch>()));
    final level = p.state(PlayerState.speakerLevel).define();
    level.set(0.5, key: 'left');
    expect(r.stateDescriptor('player.speaker.level')!.key, 'speaker');
    expect(asAnn.state(PlayerState.speakerLevel).read(key: 'left'), 0.5);
  });

  test('commands take their params, defaults filled and bounds held', () async {
    final played = <PlayerPlay>[];
    p.state(PlayerState.volume).define();
    p.registerKind(EntityKind('speaker', list: () => [EntityRef('left')]));
    p.command(PlayerCommand.play).define((c) => played.add(c.params));
    p.command(PlayerCommand.skip).define((c) => c.params.count * 2);
    p.command(PlayerCommand.setVolume).define((_) {});
    final done = await asAnn.call('player.play', {
      'track': {'title': 'A'},
      'on': 'left',
    });
    expect(done.ok, isTrue, reason: '$done');
    expect(played.single.repeat, Repeat.off);
    expect(played.single.track.title, 'A');
    expect(played.single.on, 'left');
    final skipped = await asAnn.command(PlayerCommand.skip).call((count: 3));
    expect((skipped as CallDone<int>).value, 6);
    final loud = await asAnn.command(PlayerCommand.setVolume).call((
      volume: 101,
    ));
    expect((loud as CallRefused).code, Refusal.invalidParams);
    expect(PlayerCommand.stop.params, same(RecordShape.none));
  });

  test('a query answers its type, a fact says its payload', () async {
    p
        .query(PlayerQuery.search)
        .define(
          (q) =>
              [Track(title: q.params.text)].take(q.params.limit ?? 9).toList(),
        );
    final found = await asAnn.query(PlayerQuery.search).ask((
      text: 'B',
      limit: null,
    ));
    expect((found as CallDone<List<Track>>).value.single.title, 'B');
    final long = await asAnn.query(PlayerQuery.search).ask((
      text: 'x' * 41,
      limit: null,
    ));
    expect((long as CallRefused).code, Refusal.invalidParams);

    final finished = p.fact(PlayerFact.finished).define();
    finished.emit(const Track(title: 'C'));
    expect((await asAnn.recent('player.finished', 9)).single.payload, {
      'title': 'C',
      'length': null,
      'artist': null,
    });
  });

  test('a record is read by place as its map has it, and held alike', () {
    void byPlace<T>(RecordShape<T> s, T v) {
      final keys = s.fields.keys.toList();
      final map = s.to(v);
      for (var i = 0; i < keys.length; i++) {
        expect(s.get!(v, i), map[keys[i]], reason: keys[i]);
      }
    }

    byPlace(PlayerCommand.play.params, (
      track: const Track(title: 'a'),
      repeat: Repeat.one,
      on: 'x',
    ));
    byPlace(PlayerQuery.search.params, (text: 'a', limit: 3));
    byPlace(PlayerCommand.skip.params, (count: 2));

    final search = PlayerQuery.search.params;
    String? why(Object? Function() check) {
      try {
        check();
        return null;
      } on TypeMismatch catch (e) {
        return '$e';
      }
    }

    for (final text in ['a', 'x' * 41]) {
      final v = (text: text, limit: null);
      expect(
        why(() => search.check(v, r)),
        why(() => search.type.check(search.toJson(v), r)),
      );
    }
    expect(PlayerQuery.search.params.keptAsIs, isTrue);
    expect(
      PlayerCommand.play.params.keptAsIs,
      isFalse,
      reason: 'a class that serializes itself is kept as its JSON',
    );
  });

  test('a part takes the client\'s interface: a stand-in fits it', () async {
    int? shown(IPlayerClient player) => player.volume;

    expect(shown(_StandIn()), 7);
    p.attach({'deck': Deck()});
    expect(shown(PlayerClient(asAnn)), 50);
  });

  test('every word is listed once, in its vocabulary', () {
    expect(playerWords.words.map((w) => w.name), [
      'player.volume',
      'player.repeat',
      'player.playing',
      'player.speaker.level',
      'player.volume.set',
      'player.play',
      'player.skip',
      'player.stop',
      'player.search',
      'player.clipped',
      'player.finished',
    ]);
  });

  test('the schema is kept, and a change to a published word is told', () {
    final file = File('test/fixtures/player.schema.json');
    final now = schemaOf(playerWords.words);
    if (Platform.environment['UPDATE_SCHEMA'] == '1') {
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(now)}\n',
      );
    }
    final before = (jsonDecode(file.readAsStringSync()) as Map)
        .cast<String, Object?>();
    expect(schemaBreaks(before, now), isEmpty);

    final changed = {...now}..remove('player.stop');
    changed['player.volume'] = {
      'is': 'state',
      'type': {'type': 'text'},
    };
    changed['player.next'] = {'is': 'command', 'params': <String, Object?>{}};
    expect(schemaBreaks(now, changed), [
      'player.volume changed',
      'player.stop is gone',
    ]);
  });

  group('the owner base', () {
    late Deck deck;
    setUp(() {
      deck = Deck();
      p.attach({'deck': deck});
    });

    test('defines every word, and an owner writes only its handlers', () {
      expect(r.stateDescriptor('player.volume')!.meta, {
        'label': 'Volume',
        'steps': [0, 50, 100],
      });
      expect(asAnn.state(PlayerState.volume).read(), 50);
      expect(
        r.commandDescriptor('player.play')!.deadline,
        const Duration(seconds: 5),
      );
    });

    test('serves the calls through its handlers, as its part', () async {
      final done = await asAnn.command(PlayerCommand.setVolume).call((
        volume: 95,
      ));
      expect(done.ok, isTrue, reason: '$done');
      expect(asAnn.state(PlayerState.volume).read(), 95);
      expect(r.lastChange('player.volume')!.cause.by, me.child('deck'));
      expect((await asAnn.recent('player.clipped', 9)).single.payload, {
        'volume': 95,
      });
      final found = await asBob.query(PlayerQuery.search).ask((
        text: 'B',
        limit: null,
      ));
      expect((found as CallDone<List<Track>>).value.single.title, 'B');
    });

    test('says what the class says of who may call, and when', () async {
      final asGuest = await asBob.command(PlayerCommand.stop).call(());
      expect((asGuest as CallRefused).code, Refusal.notPermitted);
      expect((await asAnn.command(PlayerCommand.stop).call(())).ok, isTrue);
      expect(deck.stopped, 1);
      deck.library.clear();
      p.child('deck').availabilityChanged('player.play');
      final play = await asAnn.command(PlayerCommand.play).call((
        track: const Track(title: 'A'),
        repeat: Repeat.off,
        on: null,
      ));
      expect(play.whyNot, contains('nothing to play'));
    });
  });

  group('the client', () {
    late PlayerClient asAnn;
    setUp(() {
      p.attach({'deck': Deck()});
      asAnn = PlayerClient(r.participant(ann));
    });

    test(
      'reads and watches states, calls and asks by the class\'s params',
      () async {
        expect(asAnn.volume, 50);
        final seen = <int?>[];
        final sub = asAnn.volumeChanges.listen(seen.add);
        final clipped = <Fact<PlayerClipped>>[];
        final heard = asAnn.clippedFacts.listen(clipped.add);
        final said = <({int volume})>[];
        final payloads = asAnn.clipped.listen(said.add);
        await asAnn.setVolume(volume: 95);
        await pumpEventQueue();
        expect(seen, [50, 95]);
        expect(
          said.single.volume,
          95,
          reason: 'the interface says the payload',
        );
        await payloads.cancel();
        expect(clipped.single.payload.volume, 95);
        expect(
          clipped.single.message.cause.by,
          me.child('deck'),
          reason: 'the message comes with it',
        );
        expect(await asAnn.skip(), 1, reason: 'its default');
        expect((await asAnn.search(text: 'A')).single.title, 'A');
        expect(asAnn.status(PlayerCommand.stop), const WordReady());
        await sub.cancel();
        await heard.cancel();
      },
    );

    test('a call not done throws, with why', () async {
      final asGuest = PlayerClient(
        LocalView(r, by: const Principal('guest', 'bob')),
      );
      expect(asGuest.status(PlayerCommand.stop), const WordNotPermitted());
      await expectLater(
        asGuest.stop(),
        throwsA(
          isA<CallNotDone>().having(
            (e) => (e.result as CallRefused).code,
            'code',
            Refusal.notPermitted,
          ),
        ),
      );
    });
  });
}

/// What a test gives a part in place of the player, as mocktail makes one.
final class _StandIn implements IPlayerClient {
  @override
  int? get volume => 7;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
