/// Level 4, an agent: the same words as MCP tools. The agent learns the
/// vocabulary from the catalog; each command it may call is a tool of its
/// own, with a schema made from the word. It is one more principal, with
/// no more rights than the callers give it.
///
/// Run: `dart run example/levels/level4_agent.dart`.
library;

import 'package:parlance/mcp.dart';
import 'package:parlance/registry.dart';

import 'player.dart';

Future<void> main() async {
  print('Level 4: an agent');
  final r = Registry();
  definePlayer(r);

  // The curated tools, and with commandTools each command the agent may
  // call as a tool of its own, its schema made from the word.
  final tools = await parlanceTools(
    LocalBoard(r, by: Who.agent),
    commandTools: true,
  );
  print('  its tools: ${[for (final t in tools) t.name].join(', ')}');

  final setVolume = tools.firstWhere(
    (t) => t.name == commandToolName(PlayerCommand.setVolume.name),
  );
  print('  ${setVolume.name}: ${setVolume.description}');
  print('  its params: ${setVolume.properties}');

  final answer = await setVolume.run({'volume': 20});
  print('  the agent turns it to 20: ${answer.text.trim()}');

  // A guest's agent gets no tool for a command its guest may not call.
  final guestTools = await parlanceTools(
    LocalBoard(r, by: Who.guest),
    commandTools: true,
  );
  print(
    "  a guest's tools: ${[for (final t in guestTools) t.name].join(', ')}",
  );
  print('  the volume: ${r.state(PlayerState.volume).read()}');
  await r.dispose();
}
