import 'dart:async';

import 'package:parlance/app.dart' show WordAccess;
import 'package:parlance/schema.dart';
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

import 'fixtures/player.dart';

/// Each call of a client takes its own token (`cancel:`): cancelled, that
/// call throws `CallNotDone` of `CallCancelled`, and the owner serving it
/// is told by `expired`; the client and its other calls go on.
final class SlowDeck extends PlayerOwnerBase {
  SlowDeck() {
    volume.set(50);
    repeat.set(Repeat.off);
    playing.set(null);
  }

  final Completer<void> release = Completer();
  final List<String> told = [];
  CancellationToken? expiredOutside;

  @override
  Future<void> play({
    required Track track,
    Repeat repeat = Repeat.off,
    String? on,
  }) async {
    expired!.whenCancelled.then((_) => told.add(track.title));
    await release.future;
    playing.set(track);
  }

  @override
  String? whyNotPlay() => null;

  @override
  void setVolume({required int volume}) {
    expiredOutside = expired;
  }

  @override
  int skip({int count = 1}) => count;

  @override
  void stop() {}

  @override
  List<Track> search({required String text, int? limit}) => const [];
}

void main() {
  late TestHost host;
  late SlowDeck deck;

  setUp(() {
    host = TestHost();
    deck = SlowDeck();
    host.participant(
      const Principal('deck'),
      owners: [deck],
      access: const WordAccess(callers: Callers.anyone),
    );
  });
  tearDown(() => host.dispose());

  test('a call cancelled throws CallNotDone of cancelled; the owner '
      'serving it is told, and what it then does stands', () async {
    final player = IPlayerClient(host.participant(const Principal('listener')));
    final stop = CancellationToken();
    final play = player.play(
      track: const Track(title: 'A'),
      cancel: stop,
    );
    await host.settle();
    stop.cancel();
    await expectLater(
      play,
      throwsA(
        isA<CallNotDone>().having(
          (e) => e.result,
          'result',
          isA<CallCancelled>(),
        ),
      ),
    );
    await host.settle();
    expect(deck.told, ['A'], reason: 'the owner heard it expired');

    deck.release.complete();
    await host.settle();
    expect(host.written(PlayerState.playing).last?.title, 'A');
  });

  test('a token cancels its own call only: the client and its other calls '
      'go on', () async {
    final player = IPlayerClient(host.participant(const Principal('listener')));
    final first = CancellationToken();
    final a = player.play(
      track: const Track(title: 'A'),
      cancel: first,
    );
    final b = player.play(
      track: const Track(title: 'B'),
      cancel: CancellationToken(),
    );
    await host.settle();
    first.cancel();
    await expectLater(a, throwsA(isA<CallNotDone>()));
    deck.release.complete();
    await b;
    await player.setVolume(volume: 20);
    expect(deck.told, ['A']);
  });

  test('expired is there while a handler serves a call', () async {
    final player = IPlayerClient(host.participant(const Principal('listener')));
    await player.setVolume(volume: 10);
    expect(deck.expiredOutside, isNotNull);
    expect(deck.expired, isNull, reason: 'outside a handler, none');
  });
}
