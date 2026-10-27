import 'dart:async';

import 'package:test/test.dart';

import '../example/main.dart' as example;

/// The example runs start to end and shows what it says it shows.
void main() {
  test('the house example runs', () async {
    final lines = <String>[];
    await runZoned(
      example.main,
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => lines.add(line),
      ),
    );
    final out = lines.join('\n');
    for (final expected in [
      'links taken: 6, problems: 0',
      'bob, a guest, sets the heating: refused (notPermitted)',
      'ann lights a room there is not: refused (invalidParams)',
      'for bob: house.heat.set notPermitted, house.light.set ready, '
          'garage.open missing',
      'why: on behalf of house/devices, through [motion-light]',
      'the hall light after motion: true',
      'through [motion-light]',
      'heating at night: 17 °C',
      'held by night-heat: house.heat.target = 17',
      'heating in the morning: 20 °C',
      'ann unlocks at night: refused (denied by night-door, overridable)',
      'ann unlocks at night, overriding: done',
      "ann's phone unlocks while away: refused (denied by away-door): nobody is home",
      'the porch light true, called on behalf of guest/bob',
      'a moment later: the porch light false',
      'bob calls my.movie: refused (notPermitted)',
      'my.guests: true',
      'rooms lit, asked by bob: [hall]',
      'and dark: [kitchen, living, porch]',
      'the living light was written by house/devices',
      'the phone sets the heating: done',
      'the phone sees: 22 °C, mode home',
      'the phone sets 40 °C: target: above 28',
      'the kitchen switch flipped by hand: from false to true',
      'the garden cannot start: module/garden/sprinkler needs weather.rain: '
          'missing',
      'the visit owns visit.guests, visit.leave; uses house.doorbell.rang '
          '(required), house.mode (optional)',
      'guests: [bob]',
      'after the visit: visit.guests missing',
      'rings it can see: [bob, bob]',
      'the agent turns the hall light off: Done.',
    ]) {
      expect(out, contains(expected));
    }
    expect(out, isNot(contains('error:')));
  });
}
