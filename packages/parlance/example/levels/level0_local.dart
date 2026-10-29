/// Level 0, a local registry: the player's words, its owner and the knob,
/// in one process, keeping nothing past what is now. Level 1 is the same
/// code on a `Registry`: only `main` changes.
///
/// Run: `dart run example/levels/level0_local.dart`.
library;

import 'package:parlance/participant.dart';

import 'player.dart';

Future<void> main() async {
  print('Level 0: a local registry');
  final r = LocalRegistry();
  // The player's commands are anyone's to call here: a Registry asks who.
  final player = r.participant(Who.player, vocabularies: [playerWords])
    ..attach({'deck': Player()});

  final ann = r.participant(Who.listener);
  final knob = Knob(
    volume: ann.state(PlayerState.volume).reader(),
    setVolume: ann.command(PlayerCommand.setVolume).caller,
    clipped: ann.fact(PlayerFact.clipped).listener,
  );
  await knob.turnTo(70);
  await knob.turnTo(95);
  await ann.settle();

  // The rules hold here too: the player's words are the player's, and a
  // value out of range is refused.
  try {
    ann.state(PlayerState.volume).define();
  } on NotPermitted catch (e) {
    print('  ann defines player.volume: ${e.message}');
  }
  final tooLoud = await ann.command(PlayerCommand.setVolume).call((
    volume: 150,
  ));
  print('  150: ${tooLoud.whyNot}');

  // A part that comes later still sees the value now, then the changes.
  final late = ann
      .state(PlayerState.volume)
      .watch()
      .listen((v) => print('  a late part sees: $v'));
  await ann.settle();
  await late.cancel();
  player.dispose();
  await r.dispose();
}
