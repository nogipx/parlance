import 'dart:async';

import 'package:test/test.dart';
import 'package:parlance_mcp/parlance_mcp.dart';

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
      'its tools: providers, describe, read, call, recent_facts, why, ${commandToolName('notes/notes.add')}',
      '${commandToolName('notes/notes.add')}: {text: {type: string, maxLength: 500}}',
      'the agent adds a note: Done.',
      "a guest's tools: providers, describe, read, call, recent_facts, why",
    ]);
  });
}
