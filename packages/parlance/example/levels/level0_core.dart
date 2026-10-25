/// Level 0, the core: two parts of one app talk, no names, no registry.
///
/// A cell holds the volume (a state), a port serves setting it (a
/// command), a signal says it clipped (a fact). The player owns all three;
/// the knob gets them through the interfaces.
///
/// Run: `dart run example/levels/level0_core.dart`.
library;

import 'package:parlance/core.dart';

import 'player.dart';

Future<void> main() async {
  print('Level 0: the core');

  // The player: the only writer of its cell, the one who serves its port
  // and says its signal.
  final volume = Cell<int>();
  final setVolume = Port<SetVolume, void>();
  final clipped = Signal<Clipped>();

  final write = volume.claim()..set(50);
  final say = clipped.claim();
  setVolume.serve((p) {
    write.set(p.volume);
    if (p.volume > loud) say.emit((volume: p.volume));
  });

  // Nobody else may write the volume: the player holds the only writer.
  try {
    volume.claim();
  } on StateError catch (e) {
    print('  a second writer: refused (${e.message})');
  }

  final knob = Knob(volume: volume, setVolume: setVolume, clipped: clipped);
  await knob.turnTo(70);
  await knob.turnTo(95);
  await settle();

  // A part that comes later still sees the value now, then the changes.
  final late = volume.watch().listen((v) => print('  a late part sees: $v'));
  await settle();
  await late.cancel();
}
