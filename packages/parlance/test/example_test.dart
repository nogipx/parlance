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
      'the hall light after motion: true',
      'through [motion-light]',
      'heating at night: 17 °C',
      'held by night-heat: heat.target = 17',
      'heating in the morning: 20 °C',
      'ann unlocks at night: refused (denied by night-door, overridable)',
      'ann unlocks at night, overriding: done',
      "ann's phone unlocks while away: refused (denied by away-door): nobody is home",
      'the porch light true, called on behalf of guest:bob',
      'a moment later: the porch light false',
      'bob calls my.movie: refused (notPermitted)',
      'my.guests: true',
      'the phone sees: 22 °C, mode home',
      'rings it can see: [bob]',
      'the agent turns the hall light off: Done.',
    ]) {
      expect(out, contains(expected));
    }
    expect(out, isNot(contains('error:')));
  });
}
