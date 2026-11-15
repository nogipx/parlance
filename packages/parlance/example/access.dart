/// Run: fvm dart run example/access.dart.
library;

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart' show HostRegistry;

import 'house/house.dart';
import 'house/words.dart';

Future<void> main() async {
  final host = Host();
  final devices = Devices();
  final warnings = host.registry.accessWarnings.listen((event) {
    print('warning: ${event.by} ${event.operation.name} ${event.word}');
  });
  const target = Principal('module', 'work');
  host.participant(
    target,
    owners: [Home(devices)],
    access: const WordAccess(callers: Who.household),
  );
  final bob = host.participant(Who.bob);
  final house = IHouseClient(participant: bob, target: target);
  // The annotation permits guests with a developer warning.
  await house.setLight(room: 'kitchen', on: true);
  final address = WordAddress(target, HouseCommand.setLight.name);
  host.setAccess(
    address: address,
    access: WordAccess(callers: Callers.only(['resident'])),
  );
  print('restricted: ${house.status(HouseCommand.setLight)}');
  // The state remains; clearing restores the annotation and warning behavior.
  host.clearAccess(address: address);
  await house.setLight(room: 'kitchen', on: false);
  await bob.settle();
  print(
    'restored: ${house.status(HouseCommand.setLight)}, light=${house.light.of('kitchen')}',
  );
  await warnings.cancel();
  await host.dispose();
  await devices.close();
}
