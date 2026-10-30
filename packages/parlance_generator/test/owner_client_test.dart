import 'package:parlance/app.dart';
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

import 'fixtures/fan.dart';
import 'fixtures/player.dart';
import 'generated_test.dart' show Deck;

/// An owner that uses another's words through their client, made in its
/// constructor (`IPlayerClient.of(this)`): it hears and reads them once
/// it is attached, here and on a guest, with no participant in hand.
final class Fan extends FansOwnerBase {
  Fan() {
    // What it reads of another's it watches: across a connection a state
    // is kept only while watched.
    listen(on: player.volume.changes, onData: (v) => volume = v);
    hear(
      fact: player.clipped,
      onData: (c) => heard.add((c.volume, player.volume.value)),
    );
  }

  int? volume;

  late final IPlayerClient player = IPlayerClient.of(this);

  /// What it heard, and the volume it read then.
  final List<(int, int?)> heard = [];
}

void main() {
  for (final across in [false, true]) {
    test('an owner hears and reads another\'s words through its client '
        '(${across ? 'on a guest' : 'here'})', () async {
      final host = TestHost();
      addTearDown(host.dispose);
      host.participant(
        const Principal('player'),
        owners: [Deck()],
        access: const WordAccess(callers: Callers.anyone),
      );
      final fan = Fan();
      const listener = Principal('listener', 'ann');
      if (across) {
        await (await host.join(
          listener,
          vocabularies: [fansWords],
        )).attach([fan]);
      } else {
        host.participant(listener, owners: [fan]);
      }
      await host.settle();

      await fan.player.setVolume(volume: 95);
      await host.settle();
      expect(fan.heard, [(95, 95)]);
      expect(fan.volume, 95);
    });
  }

  test('an owner on a guest the host did not grant its vocabulary is '
      'refused, told what to grant and where', () async {
    final host = TestHost();
    addTearDown(host.dispose);
    final side = await host.join(const Principal('player'));
    expect(
      () => side.attach([Deck()]),
      throwsA(
        isA<NotPermitted>().having(
          (e) => '$e',
          'message',
          allOf(
            contains(
              'Deck, attached as player@player, owns the words of '
              'the vocabulary player',
            ),
            contains(
              'host.participant(player, '
              'vocabularies: [playerWords]).serve(endpoint)',
            ),
          ),
        ),
      ),
    );
  });

  test('its client used before it is attached says so', () {
    expect(() => Fan().player.volume.value, throwsStateError);
  });
}
