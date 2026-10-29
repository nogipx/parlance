/// Level 1, the registry: the same parts, now with named words, rights and
/// causes. The player is an owner on a participant main makes; the knob is
/// the same class, and only where its handles come from changes: a
/// listener's participant.
///
/// Run: `dart run example/levels/level1_registry.dart`.
library;

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';

import 'player.dart';

Future<void> main() async {
  print('Level 1: the registry');
  final r = Registry();
  final player = startPlayer(r);

  // Each part sees the registry through its own participant, as itself.
  final ann = r.participant(Who.listener);
  final knob = Knob(
    volume: ann.state(PlayerState.volume).reader(),
    setVolume: ann.command(PlayerCommand.setVolume).caller,
    clipped: ann.fact(PlayerFact.clipped).listener,
  );
  await knob.turnTo(70);
  await knob.turnTo(95);
  await ann.settle();

  // Rights: a guest is not among the command's callers, and can see so
  // before it calls.
  final bob = r.participant(Who.guest);
  final turn = bob.command(PlayerCommand.setVolume);
  print('  for a guest the command is ${turn.status}');
  final asGuest = await turn.call((volume: 10));
  print('  a guest turns it: ${asGuest.whyNot}');
  // Nor may it put words in the player's vocabulary.
  try {
    bob.state(PlayerState.volume).define();
  } on NotPermitted catch (e) {
    print('  a guest defines player.volume: ${e.message}');
  }

  // Types: the word says 0..100.
  final tooLoud = await ann.command(PlayerCommand.setVolume).call((
    volume: 150,
  ));
  print('  150: ${tooLoud.whyNot}');

  // Causes: why the volume is what it is, and which part wrote it.
  final why = r.explain(PlayerState.volume.name);
  final call = why.trail.first;
  print(
    '  why ${why.value}: ${call.cause.by} called ${call.command}, '
    'and ${why.change?.cause.by} wrote it',
  );

  // The catalog: what anyone joining can learn without knowing the player.
  print('  words: ${[for (final d in r.catalog) d.name]}');
  player.dispose();
  await r.dispose();
}
