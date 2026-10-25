/// Level 2, links: wiring made of words and kept as data. Here a limiter:
/// when the player says it clipped, turn the volume back to 80. Neither
/// the player nor the knob knows the link exists.
///
/// Run: `dart run example/levels/level2_links.dart`.
library;

import 'package:parlance/links.dart';
import 'package:parlance/registry.dart';

import 'player.dart';

Future<void> main() async {
  print('Level 2: links');
  final r = Registry();
  definePlayer(r);
  final links = Links(r);

  // Data, not code: a user could have written it in an editor.
  final problems = links.source('limiter', [
    {
      'id': 'limiter',
      'name': 'Back to 80 when it clips',
      'when': [PlayerFact.clipped.trigger()],
      'do': [PlayerCommand.setVolume.step((volume: 80))],
    },
  ]);
  print('  links taken: ${links.links.length}, problems: ${problems.length}');

  final knob = Knob(
    volume: r.state(PlayerState.volume).reader(),
    setVolume: r.command(PlayerCommand.setVolume).caller(by: Who.listener),
    clipped: r.fact(PlayerFact.clipped).listener,
  );
  await knob.turnTo(95);
  await settle();
  print('  after the link: ${r.state(PlayerState.volume).read()}');

  // The cause names the link, so it is clear who set 80 and why.
  final why = r.explain(PlayerState.volume.name);
  print('  why 80: ${why.trail.first.cause.by} called it');

  await links.dispose();
  await r.dispose();
}
