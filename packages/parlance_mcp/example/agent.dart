/// An agent: the same words as MCP tools. It learns the vocabulary from
/// the catalog; each command it may call is a tool of its own, with a
/// schema made from the word. It is one more principal, with no more
/// rights than the callers give it.
///
/// Run: `dart run example/agent.dart`.
library;

import 'package:parlance/app.dart';
import 'package:parlance_mcp/parlance_mcp.dart';

import 'notes.dart';

Future<void> main() async {
  final host = Host();
  host.participant(const Principal('notes'), vocabularies: [notesWords]).attach(
    [Book()],
  );

  // The curated tools, and with commandTools each command the agent may
  // call as a tool of its own, its schema made from the word.
  final tools = await parlanceTools(
    host.participant(const Principal('agent', 'demo')),
    commandTools: true,
  );
  print('its tools: ${[for (final t in tools) t.name].join(', ')}');

  final add = tools.firstWhere(
    (t) => t.name == commandToolName(NotesCommand.add.name),
  );
  print('${add.name}: ${add.properties}');
  print(
    'the agent adds a note: ${(await add.run({'text': 'milk'})).text.trim()}',
  );

  // A guest's agent gets no tool for a command it may not call.
  final guest = await parlanceTools(
    host.participant(const Principal('guest', 'bob')),
    commandTools: true,
  );
  print("a guest's tools: ${[for (final t in guest) t.name].join(', ')}");
  await host.dispose();
}
