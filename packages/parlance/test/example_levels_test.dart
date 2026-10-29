import 'dart:async';

import 'package:test/test.dart';

import '../example/levels/core.dart' as core;
import '../example/levels/level0_local.dart' as local;
import '../example/levels/level1_registry.dart' as registry;
import '../example/levels/level3_remote.dart' as remote;

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
    'local': (
      local.main,
      [
        'knob shows: 95',
        'knob hears: clipped at 95',
        'ann defines player.volume: listener/ann defines in no vocabulary',
        '150: volume: above 100',
        'a late part sees: 95',
      ],
    ),
    'registry': (
      registry.main,
      [
        'knob hears: clipped at 95',
        'for a guest the command is notPermitted',
        'a guest turns it: guest/bob may not call player.volume.set',
        'a guest defines player.volume: guest/bob defines in no vocabulary',
        '150: volume: above 100',
        'why 95: listener/ann called player.volume.set, and player@deck '
            'wrote it',
        'words: [player.volume, player.volume.set, player.clipped]',
      ],
    ),
    'remote': (
      remote.main,
      [
        'the phone joined as phone/ann-phone',
        'knob shows: 30',
        'knob hears: clipped at 96',
        'knob shows: 96',
        'the host sees: 96',
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
