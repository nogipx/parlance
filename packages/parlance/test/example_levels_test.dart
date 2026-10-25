import 'dart:async';

import 'package:test/test.dart';

import '../example/levels/level0_core.dart' as core;
import '../example/levels/level1_registry.dart' as registry;
import '../example/levels/level2_links.dart' as links;
import '../example/levels/level3_remote.dart' as remote;
import '../example/levels/level4_agent.dart' as agent;

/// Every level of the example runs and shows what it says it shows.
void main() {
  Future<String> run(Future<void> Function() level) async {
    final lines = <String>[];
    await runZoned(
      level,
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => lines.add(line),
      ),
    );
    return lines.join('\n');
  }

  final expected = <String, (Future<void> Function(), List<String>)>{
    'core': (
      core.main,
      [
        'a second writer: refused',
        'knob shows: 95',
        'knob hears: clipped at 95',
        'a late part sees: 95',
      ],
    ),
    'registry': (
      registry.main,
      [
        'knob hears: clipped at 95',
        'a guest turns it: guest:bob may not call player.volume.set',
        '150: volume: above 100',
        'why 95: listener:ann called player.volume.set, and player wrote it',
      ],
    ),
    'links': (
      links.main,
      [
        'links taken: 1, problems: 0',
        'after the link: 80',
        'why 80: link:limiter',
      ],
    ),
    'remote': (remote.main, ['the phone sees: 30', 'the host sees: 30']),
    'agent': (
      agent.main,
      [
        'player_volume_set: player.volume.set',
        "{volume: {type: integer, minimum: 0, maximum: 100}}",
        'the agent turns it to 20: Done.',
        "a guest's tools: describe, read, call, recent_facts, why, layers\n",
        'the volume: 20',
      ],
    ),
  };

  for (final MapEntry(key: name, value: (level, lines)) in expected.entries) {
    test('the $name level runs', () async {
      final out = await run(level);
      for (final line in lines) {
        expect(out, contains(line));
      }
    });
  }
}
