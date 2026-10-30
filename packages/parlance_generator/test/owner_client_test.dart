import 'package:parlance/app.dart';
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

import 'fixtures/player.dart';
import 'generated_test.dart' show Deck;

/// An owner that uses another's words through their client, made in its
/// constructor (`PlayerClient.of(this)`): it hears and reads them once
/// it is attached, here and on a guest, with no participant in hand.
final class Fan implements IOwner {
  Fan() {
    IOwner.made(this, define: (_) {});
    // What it reads of another's it watches: across a connection a state
    // is kept only while watched.
    listen(player.volume.changes, (v) => volume = v);
    hear(player.clipped, (c) => heard.add((c.volume, player.volume.value)));
  }

  int? volume;

  late final PlayerClient player = PlayerClient.of(this);

  /// What it heard, and the volume it read then.
  final List<(int, int?)> heard = [];
}

void main() {
  for (final across in [false, true]) {
    test('an owner hears and reads another\'s words through its client '
        '(${across ? 'on a guest' : 'here'})', () async {
      final host = TestHost();
      addTearDown(host.dispose);
      await host
          .participant(
            const Principal('player'),
            vocabularies: [playerWords],
            access: const WordAccess(call: Callers({'*': Access.allow})),
          )
          .attach({'deck': Deck()});
      final fan = Fan();
      final side = across
          ? await host.join(const Principal('listener', 'ann'))
          : host.participant(const Principal('listener', 'ann'));
      await side.attach({'fan': fan});
      await host.settle();

      await fan.player.setVolume(volume: 95);
      await host.settle();
      expect(fan.heard, [(95, 95)]);
      expect(fan.volume, 95);
    });
  }

  for (final across in [false, true]) {
    test('an owner where its vocabulary was not given is refused, told '
        'what to give and where (${across ? 'on a guest' : 'here'})', () async {
      final host = TestHost();
      addTearDown(host.dispose);
      const who = Principal('player');
      final side = across ? await host.join(who) : host.participant(who);
      expect(
        () => side.attach({'deck': Deck()}),
        throwsA(
          isA<NotPermitted>().having(
            (e) => '$e',
            'message',
            allOf(
              contains(
                'Deck, attached as player@deck, owns the words of '
                'the vocabulary player',
              ),
              contains(
                'host.participant(player, '
                'vocabularies: [playerWords])',
              ),
            ),
          ),
        ),
      );
    });
  }

  test('its client used before it is attached says so', () {
    expect(() => Fan().player.volume.value, throwsStateError);
  });
}
