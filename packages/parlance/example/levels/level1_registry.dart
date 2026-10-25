/// Level 1, the registry: the same parts, now with named words, rights and
/// causes. The knob is the same class; only where its handles come from
/// changes.
///
/// Run: `dart run example/levels/level1_registry.dart`.
library;

import 'package:parlance/registry.dart';

import 'player.dart';

Future<void> main() async {
  print('Level 1: the registry');
  final r = Registry();
  definePlayer(r);

  // The same knob, on the registry's typed words, acting for a listener.
  final knob = Knob(
    volume: r.state(PlayerState.volume).reader(),
    setVolume: r.command(PlayerCommand.setVolume).caller(by: Who.listener),
    clipped: r.fact(PlayerFact.clipped).listener,
  );
  await knob.turnTo(70);
  await knob.turnTo(95);
  await settle();

  // Rights: a guest is not among the command's callers.
  final asGuest = await r.command(PlayerCommand.setVolume).call((
    volume: 10,
  ), by: Who.guest);
  print('  a guest turns it: ${asGuest.whyNot}');

  // Types: the word says 0..100.
  final tooLoud = await r.command(PlayerCommand.setVolume).call((
    volume: 150,
  ), by: Who.listener);
  print('  150: ${tooLoud.whyNot}');

  // Causes: why the volume is what it is.
  final why = r.explain(PlayerState.volume.name);
  final call = why.trail.first;
  print(
    '  why ${why.value}: ${call.cause.by} called ${call.command}, '
    'and ${why.change?.cause.by} wrote it',
  );

  // The catalog: what anyone joining can learn without knowing the player.
  print('  words: ${[for (final d in r.catalog) d.name]}');
  await r.dispose();
}
