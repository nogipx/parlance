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
      'why: written by home@house, '
          'started by home/house.set_light by resident/ann',
      'answering home/house.set_light {room: kitchen, on: true} by resident/ann',
      'bob, a guest, sets the heating: refused (notPermitted)',
      'ann lights a room there is not: no room attic',
      'for bob: house.set_heat notPermitted, house.set_light ready, '
          'visit.guests missing',
      'an agent unlocks at night: refused (denied by home@house#night-door)',
      'ann unlocks at night: done',
      'rooms lit, asked by bob: [kitchen]',
      'and dark: [hall, living, porch]',
      'recorded kitchen temperatures: [20, 21, 22]',
      'the kitchen switch flipped by hand: from true to false',
      'during the visit: visit.guests ready',
      'guests: [bob]',
      'written by module/visit@visit, '
          'started by home/house.rang by guest/bob',
      'after the visit: visit.guests missing',
      'the phone sets the heating: done',
      'the phone sees: 22 °C, mode home',
      'the phone sets 40 °C: refused (invalidParams): target: above 28',
      'phone temperature now: 22 °C',
      'phone temperature next: 23 °C',
      'phone temperature subscription cancelled',
      'fact home/house.rang by guest/bob, '
          'started by home/house.rang by guest/bob\n'
          '  write module/visit/visit.guests by module/visit@visit, '
          'started by home/house.rang by guest/bob',
    ]) {
      expect(out, contains(expected));
    }
    expect(out, isNot(contains('error:')));
  });
}
