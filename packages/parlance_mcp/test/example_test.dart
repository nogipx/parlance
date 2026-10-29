import 'dart:async';

import 'package:test/test.dart';

import '../example/agent.dart' as example;

/// The example runs and shows what it says it shows.
void main() {
  test('the agent example runs', () async {
    final lines = <String>[];
    await runZoned(
      example.main,
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => lines.add(line),
      ),
    );
    expect(lines, [
      'its tools: describe, read, call, recent_facts, why, notes_add',
      'notes_add: {text: {type: string}}',
      'the agent adds a note: Done.',
      "a guest's tools: describe, read, call, recent_facts, why",
    ]);
  });
}
