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
      'ann turns the kitchen light on: done',
      'why: written by house/devices',
      'answering house.light.set {room: kitchen, on: true} by resident/ann',
      'bob, a guest, sets the heating: refused (notPermitted)',
      'ann lights a room there is not: refused (invalidParams)',
      'for bob: house.heat.set notPermitted, house.light.set ready, '
          'garage.open missing',
      'ann unlocks at night: refused (denied by night-door, overridable)',
      'ann unlocks at night, overriding: done',
      'rooms lit, asked by bob: [kitchen]',
      'and dark: [hall, living, porch]',
      'the kitchen switch flipped by hand: from true to false',
      'during the visit: visit.guests ready',
      'guests: [bob]',
      'after the visit: visit.guests missing',
      'the phone sets the heating: done',
      'the phone sees: 22 °C, mode home',
      'the phone sets 40 °C: target: above 28',
      'rings it can see: [bob]',
      'the agent turns the hall light off: Done.',
    ]) {
      expect(out, contains(expected));
    }
    expect(out, isNot(contains('error:')));
  });
}
