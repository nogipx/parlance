import 'dart:convert';
import 'dart:io';

import 'package:parlance/tools.dart';
import 'package:parlance/schema.dart';
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

import 'fixtures/player.dart';

const me = Principal('player');
const ann = Principal('listener', 'ann');
const anyone = Callers.anyone;

/// A player's owner: only its handlers, and what it sets; no cause, no
/// handle, no copy of its states.
final class Deck extends PlayerOwnerBase {
  Deck() {
    volume.set(50);
    repeat.set(Repeat.off);
    playing.set(null);
  }

  final List<Track> library = [
    const Track(title: 'A'),
    const Track(title: 'B'),
  ];
  int stopped = 0;

  @override
  void setVolume({required int volume}) {
    this.volume.set(volume);
    if (volume > 90) clipped.say(volume: volume);
  }

  @override
  Future<void> play({
    required Track track,
    Repeat repeat = Repeat.off,
    String? on,
  }) async {
    await Future<void>.delayed(Duration.zero);
    playing.set(track);
  }

  @override
  String? whyNotPlay() => library.isEmpty ? 'nothing to play' : null;

  @override
  int skip({int count = 1}) => count;

  @override
  void stop() => stopped++;

  @override
  List<Track> search({required String text, int? limit}) => [
    for (final t in library)
      if (t.title.contains(text)) t,
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
      access: const WordAccess(callers: anyone),
    );
  });
  tearDown(() => r.dispose());

  /// [p] made again, [deck] its owner.
  void attach(Deck deck) {
    p.dispose();
    p = r.participant(
      me,
      owners: [deck],
      access: const WordAccess(callers: anyone),
    );
  }

  test('states carry their values, a class through its toJson', () {
    final playing = GeneratedWords(p.raw).state(PlayerState.playing).define();
    const track = Track(title: 'Song', seconds: 200, artist: Artist('Ann'));
    playing.set(track);
    expect(asAnn.raw.read('player.playing'), {
      'title': 'Song',
      'length': 200,
      'artist': {'name': 'Ann'},
    });
    expect(
      GeneratedWords(
        asAnn.raw,
      ).stateOf(PlayerState.playing).value!.artist!.name,
      'Ann',
    );
    final volume = GeneratedWords(p.raw).state(PlayerState.volume).define();
    expect(() => volume.set(150), throwsA(isA<TypeMismatch>()));
    final level = GeneratedWords(
      p.raw,
    ).state(PlayerState.speakerLevel).define();
    level.set(0.5, key: 'left');
    expect(r.stateDescriptor('player.speaker_level')!.key, 'speaker');
    expect(
      GeneratedWords(asAnn.raw).keyedOf(PlayerState.speakerLevel).of('left'),
      0.5,
    );
  });

  test('commands take their params, defaults filled and bounds held', () async {
    final played = <PlayerPlay>[];
    GeneratedWords(p.raw).state(PlayerState.volume).define();
    p.raw.addChoices(Choices('speaker', list: () => [Choice('left')]));
    GeneratedWords(
      p.raw,
    ).command(PlayerCommand.play).serve((params) => played.add(params));
    GeneratedWords(
      p.raw,
    ).command(PlayerCommand.skip).serve((params) => params.count * 2);
    GeneratedWords(p.raw).command(PlayerCommand.setVolume).serve((_) {});
    final done = await asAnn.raw.call('player.play', {
      'track': {'title': 'A'},
      'on': 'left',
    });
    expect(done.ok, isTrue, reason: '$done');
    expect(played.single.repeat, Repeat.off);
    expect(played.single.track.title, 'A');
    expect(played.single.on, 'left');
    final skipped = await GeneratedWords(
      asAnn.raw,
    ).command(PlayerCommand.skip).call((count: 3));
    expect((skipped as CallDone<int>).value, 6);
    final loud = await GeneratedWords(
      asAnn.raw,
    ).command(PlayerCommand.setVolume).call((volume: 101));
    expect((loud as CallRefused).code, Refusal.invalidParams);
    expect(PlayerCommand.stop.params, same(RecordShape.none));
  });

  test('a query answers its type, a fact says its payload', () async {
    GeneratedWords(p.raw)
        .query(PlayerQuery.search)
        .serve(
          (params) =>
              [Track(title: params.text)].take(params.limit ?? 9).toList(),
        );
    final found = await GeneratedWords(
      asAnn.raw,
    ).query(PlayerQuery.search).ask((text: 'B', limit: null));
    expect((found as CallDone<List<Track>>).value.single.title, 'B');
    final long = await GeneratedWords(
      asAnn.raw,
    ).query(PlayerQuery.search).ask((text: 'x' * 41, limit: null));
    expect((long as CallRefused).code, Refusal.invalidParams);

    final finished = GeneratedWords(p.raw).fact(PlayerFact.finished).define();
    finished.say(const Track(title: 'C'));
    expect((await asAnn.raw.recent('player.finished', 9)).single.payload, {
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
    int? shown(IPlayerClient player) => player.volume.value;

    expect(shown(_StandIn()), 7);
    attach(Deck());
    expect(shown(IPlayerClient(asAnn)), 50);
    expect(
      IPlayerClient(asAnn).mismatches,
      isEmpty,
      reason: 'the words met are the words it was built against',
    );
  });

  test('a client made tells the registry what it was built against', () {
    IPlayerClient(asAnn);
    expect(r.mismatches, isEmpty, reason: 'nothing there yet');
    p.raw.defineState(StateDescriptor('player.volume', type: const TextType()));
    expect(r.mismatches.map((m) => (m.by, m.word)), [(ann, 'player.volume')]);
  });

  test('an enum value marked @Fallback is what one added later reads as', () {
    final shape = PlayerState.repeat.shape;
    expect(shape.fromJson('shuffle'), Repeat.off);
    expect(shape.fromJson('all'), Repeat.all);
  });

  test('every word is listed once, in its vocabulary', () {
    expect(playerWords.words.map((w) => w.name), [
      'player.volume',
      'player.repeat',
      'player.playing',
      'player.speaker_level',
      'player.volume_set',
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
      'player.volume: type.type: was int, is text',
      'player.stop is gone',
    ]);
  });

  group('the owner base', () {
    late Deck deck;
    setUp(() {
      deck = Deck();
      attach(deck);
    });

    test('defines every word, and an owner writes only its handlers', () {
      expect(r.stateDescriptor('player.volume')!.meta, {
        'label': 'Volume',
        'steps': [0, 50, 100],
      });
      expect(GeneratedWords(asAnn.raw).stateOf(PlayerState.volume).value, 50);
      expect(
        r.commandDescriptor('player.play')!.deadline,
        const Duration(seconds: 5),
      );
    });

    test('serves the calls through its handlers, as its part', () async {
      final done = await GeneratedWords(
        asAnn.raw,
      ).command(PlayerCommand.setVolume).call((volume: 95));
      expect(done.ok, isTrue, reason: '$done');
      expect(GeneratedWords(asAnn.raw).stateOf(PlayerState.volume).value, 95);
      expect(r.lastChange('player.volume')!.cause.by, me.child('player'));
      expect((await asAnn.raw.recent('player.clipped', 9)).single.payload, {
        'volume': 95,
      });
      final found = await GeneratedWords(
        asBob.raw,
      ).query(PlayerQuery.search).ask((text: 'B', limit: null));
      expect((found as CallDone<List<Track>>).value.single.title, 'B');
    });

    test('what a handler writes and says follows from the call, after an '
        'await too', () async {
      await GeneratedWords(
        asAnn.raw,
      ).command(PlayerCommand.setVolume).call((volume: 95), id: 'v1');
      expect(r.lastChange('player.volume')!.cause.parent, 'v1');
      expect(
        (await asAnn.raw.recent('player.clipped', 9)).single.cause.parent,
        'v1',
      );
      await GeneratedWords(asAnn.raw).command(PlayerCommand.play).call((
        track: const Track(title: 'A'),
        repeat: Repeat.off,
        on: null,
      ), id: 'p1');
      expect(r.lastChange('player.playing')!.cause.parent, 'p1');
      expect(deck.playing.value?.title, 'A', reason: 'what it set, it reads');
    });

    test('a state is removed by remove, and set again', () {
      deck.volume.remove();
      expect(deck.volume.value, isNull);
      expect(asAnn.raw.readAll('player.volume'), isEmpty);
      deck.volume.set(7);
      expect(GeneratedWords(asAnn.raw).stateOf(PlayerState.volume).value, 7);
    });

    test('the choices its words name are constants, for an owner', () {
      expect(PlayerChoices.speaker, 'speaker');
    });

    test('keyed states, set and removed by key', () async {
      deck.speakerLevel.set('left', 0.5);
      deck.speakerLevel.set('right', 1);
      deck.speakerLevel.remove('right');
      expect(deck.speakerLevel.of('left'), 0.5);
      expect(deck.speakerLevel.all, {'left': 0.5});
      expect(GeneratedWords(asAnn.raw).keyedOf(PlayerState.speakerLevel).all, {
        'left': 0.5,
      });
    });

    test('says what the class says of who may call, and when', () async {
      final asGuest = await GeneratedWords(
        asBob.raw,
      ).command(PlayerCommand.stop).call(());
      expect((asGuest as CallRefused).code, Refusal.notPermitted);
      expect(
        (await GeneratedWords(
          asAnn.raw,
        ).command(PlayerCommand.stop).call(())).ok,
        isTrue,
      );
      expect(deck.stopped, 1);
      deck.library.clear();
      p.raw.child('player').raw.availabilityChanged('player.play');
      final play = await GeneratedWords(asAnn.raw)
          .command(PlayerCommand.play)
          .call((track: const Track(title: 'A'), repeat: Repeat.off, on: null));
      expect(play.why, contains('nothing to play'));
    });
  });

  test('an owner not attached keeps what it set and said, for a test', () {
    final deck = Deck()..setVolume(volume: 95);
    expect(deck.volume.value, 95);
    expect(saidBy(deck, PlayerFact.clipped), [(volume: 95)]);
    expect(deck.skip(count: 2), 2);
  });

  group('the client', () {
    late Deck deck;
    late IPlayerClient asAnn;
    setUp(() {
      attach(deck = Deck());
      asAnn = IPlayerClient(r.participant(ann));
    });

    test('watches a keyed state whole: every key, as any comes, changes '
        'or goes', () async {
      final seen = <Map<String, num>>[];
      final sub = asAnn.speakerLevel.changes.listen(seen.add);
      await pumpEventQueue();
      deck.speakerLevel.set('left', 0.5);
      await pumpEventQueue();
      deck.speakerLevel.remove('left');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [
        <String, num>{},
        {'left': 0.5},
        <String, num>{},
      ]);
    });

    test(
      'reads and watches states, calls and asks by the class\'s params',
      () async {
        expect(asAnn.volume.value, 50);
        final seen = <int?>[];
        final sub = asAnn.volume.changes.listen(seen.add);
        final clipped = <Fact<PlayerClipped>>[];
        final heard = asAnn.clipped.facts.listen(clipped.add);
        final said = <({int volume})>[];
        final payloads = asAnn.clipped.payloads.listen(said.add);
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
          me.child('player'),
          reason: 'the message comes with it',
        );
        expect(
          [for (final f in await asAnn.clipped.recent(5)) f.payload.volume],
          [95],
          reason: 'what was said before, for a screen opened late',
        );
        expect(await asAnn.skip(), 1, reason: 'its default');
        expect((await asAnn.search(text: 'A')).single.title, 'A');
        expect(asAnn.status(PlayerCommand.stop), const WordReady());
        await sub.cancel();
        await heard.cancel();
      },
    );

    test('a call not done throws, with why', () async {
      final asGuest = IPlayerClient(
        r.participant(const Principal('guest', 'bob')),
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

/// What a test gives a part in place of the player, as mocktail makes one,
/// its state a stub of the library's.
final class _StandIn implements IPlayerClient {
  @override
  final IStateOf<int> volume = StateStub(7);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
