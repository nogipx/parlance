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
    volume.set(level, cause: call.causeFor(participant.who));
    if (level > 90) {
      clipped.emit((volume: level), cause: call.causeFor(participant.who));
    }
  }

  @override
  Future<void> play(CommandCallOf<PlayerPlay> call) async {
    playing.set(call.params.track, cause: call.causeFor(participant.who));
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
  setUp(() {
    r = Registry(onError: (e, st) => throw e);
    p = r.participant(
      me,
      namespaces: {'player'},
      access: const WordAccess(call: anyone),
    );
  });
  tearDown(() => r.dispose());

  test('states carry their values, a class through its toJson', () {
    final playing = p.state(PlayerState.playing).define();
    const track = Track(title: 'Song', seconds: 200, artist: Artist('Ann'));
    playing.set(track);
    expect(r.read('player.playing'), {
      'title': 'Song',
      'length': 200,
      'artist': {'name': 'Ann'},
    });
    expect(r.state(PlayerState.playing).read()!.artist!.name, 'Ann');
    final volume = p.state(PlayerState.volume).define();
    expect(() => volume.set(150), throwsA(isA<TypeMismatch>()));
    final level = p.state(PlayerState.speakerLevel).define();
    level.set(0.5, key: 'left');
    expect(r.stateDescriptor('player.speaker.level')!.key, 'speaker');
    expect(r.state(PlayerState.speakerLevel).read(key: 'left'), 0.5);
  });

  test('commands take their params, defaults filled and bounds held', () async {
    final played = <PlayerPlay>[];
    p.state(PlayerState.volume).define();
    p.registerKind(EntityKind('speaker', list: () => [EntityRef('left')]));
    p.command(PlayerCommand.play).define((c) => played.add(c.params));
    p.command(PlayerCommand.skip).define((c) => c.params.count * 2);
    p.command(PlayerCommand.setVolume).define((_) {});
    final done = await r.call('player.play', {
      'track': {'title': 'A'},
      'on': 'left',
    }, by: ann);
    expect(done.ok, isTrue, reason: '$done');
    expect(played.single.repeat, Repeat.off);
    expect(played.single.track.title, 'A');
    expect(played.single.on, 'left');
    final skipped = await r.command(PlayerCommand.skip).call((
      count: 3,
    ), by: ann);
    expect((skipped as CallDone<int>).value, 6);
    final loud = await r.command(PlayerCommand.setVolume).call((
      volume: 101,
    ), by: ann);
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
    final found = await r.query(PlayerQuery.search).ask((
      text: 'B',
      limit: null,
    ), by: ann);
    expect((found as CallDone<List<Track>>).value.single.title, 'B');
    final long = await r.query(PlayerQuery.search).ask((
      text: 'x' * 41,
      limit: null,
    ), by: ann);
    expect((long as CallRefused).code, Refusal.invalidParams);

    final finished = p.fact(PlayerFact.finished).define();
    finished.emit(const Track(title: 'C'));
    expect(r.recent('player.finished').single.payload, {'title': 'C'});
  });

  test('every word is listed once, in the namespace', () {
    expect(PlayerWords.all.map((w) => w.name), [
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
    final now = schemaOf(PlayerWords.all);
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
    late Owners owners;
    setUp(() {
      deck = Deck();
      owners = Owners(p, {'deck': deck});
    });

    test('defines every word, and an owner writes only its handlers', () {
      expect(r.state(PlayerState.volume).read(), 50);
      expect(r.declarations[me.child('deck')]!.owns, {
        for (final w in PlayerWords.all) w.name,
      });
      expect(
        r.commandDescriptor('player.volume.set')!.sets!.state,
        'player.volume',
      );
      expect(
        r.commandDescriptor('player.play')!.deadline,
        const Duration(seconds: 5),
      );
    });

    test('serves the calls through its handlers, as its part', () async {
      final done = await r.command(PlayerCommand.setVolume).call((
        volume: 95,
      ), by: ann);
      expect(done.ok, isTrue, reason: '$done');
      expect(r.state(PlayerState.volume).read(), 95);
      expect(r.lastChange('player.volume')!.cause.by, me.child('deck'));
      expect(r.recent('player.clipped').single.payload, {'volume': 95});
      final found = await r.query(PlayerQuery.search).ask((
        text: 'B',
        limit: null,
      ), by: const Principal('guest', 'bob'));
      expect((found as CallDone<List<Track>>).value.single.title, 'B');
    });

    test('says what the class says of who may call, and when', () async {
      final asGuest = await r
          .command(PlayerCommand.stop)
          .call((), by: const Principal('guest', 'bob'));
      expect((asGuest as CallRefused).code, Refusal.notPermitted);
      expect(
        (await r.command(PlayerCommand.stop).call((), by: ann)).ok,
        isTrue,
      );
      expect(deck.stopped, 1);
      deck.library.clear();
      p.child('deck').availabilityChanged('player.play');
      final play = await r.command(PlayerCommand.play).call((
        track: const Track(title: 'A'),
        repeat: Repeat.off,
        on: null,
      ), by: ann);
      expect(play.whyNot, contains('nothing to play'));
    });

    tearDown(() => owners.dispose());
  });

  group('the client', () {
    late Owners owners;
    late PlayerClient asAnn;
    setUp(() {
      owners = Owners(p, {'deck': Deck()});
      asAnn = PlayerClient(r.participant(ann));
    });
    tearDown(() => owners.dispose());

    test(
      'reads and watches states, calls and asks by the class\'s params',
      () async {
        expect(asAnn.volume, 50);
        final seen = <int?>[];
        final sub = asAnn.volumeChanges.listen(seen.add);
        final clipped = <PlayerClipped>[];
        final heard = asAnn.clipped.listen(clipped.add);
        await asAnn.setVolume(volume: 95);
        await pumpEventQueue();
        expect(seen, [50, 95]);
        expect(clipped.single.volume, 95);
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
