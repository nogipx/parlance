# parlance_mcp

Inspect running Parlance apps and their logs through one MCP connection.

[parlance](https://pub.dev/packages/parlance) gives every part of an app a
shared language of states, commands, queries and facts. This package speaks
that language with an AI agent: it serves the words of a running host as
curated [MCP](https://modelcontextprotocol.io) tools, so an agent reads what
is so, calls commands and hears facts like any other part.

Apps connect to the collector over WebSocket. An agent connects once to the
collector's local MCP socket to inspect any connected app.

## Collect logs and inspect live hosts

Install and start the collector on macOS or Linux:

```sh
dart pub global activate parlance_mcp
mkdir -p -m 700 "$HOME/.parlance"
parlance-mcp --socket "$HOME/.parlance/mcp.sock"
```

Configure the agent's stdio MCP command once as `nc -U /absolute/path/to/.parlance/mcp.sock`.
The collector stays running when an agent exits. Its default listeners are
`ws://127.0.0.1:9502` for hosts and `ws://127.0.0.1:9500` for
existing `rpc_dart_log` clients. For a phone on a trusted network, set
`--bind` to the computer's LAN address. Both ingress ports accept unauthenticated
devices. Use a trusted TLS endpoint for clients that require `wss`.

Add `parlance_mcp` to your app with `dart pub add parlance_mcp`. Attach the
collector to the host and its log controller when diagnostics are enabled:

```dart
import 'package:parlance/app.dart';
import 'package:parlance_mcp/collector_host.dart';

final diagnostics = CollectorHost(
  host: host,
  principal: const Principal('diagnostics'),
  logs: logController,
  app: 'Notes',
  device: 'Phone / personal vault',
  address: Uri.parse('ws://192.168.1.10:9502'),
);
// On shutdown or when diagnostics are disabled:
await diagnostics.close();
```

The connector retries the outgoing connection and attaches a log output with
the same device label shown by `hosts`. Use a dedicated principal with the
host's intended access. Pass `logAddress` for a custom log port or proxy path.

Call `hosts` to find a session prefix such as `h1`. The agent can use
`h1_targets`, `h1_describe`, `h1_read`, `h1_why` and `h1_recent_facts`.
A reconnected host gets a new prefix. `rpc_log_sources` and
`rpc_log_get_logs` also work while the host is offline. Use the full device
label from `hosts` to filter records from one app instance. Logs stay in
memory until eviction or collector shutdown.

Set `commandTools: true` on a host to expose its `call` tool and individual
commands permitted for its principal. Other hosts keep their own settings.

To try it from a checkout, run `dart run example/collector_host.dart` in the
package directory while the collector is running. In the agent, list `hosts`,
inspect the Notes host and search its logs for `Notes host ready`.

A whole small host with an agent's vocabulary:
[`example/`](https://github.com/nogipx/parlance/tree/main/packages/parlance_mcp/example)
(`example/agent.dart` runs one, `example/notes.dart` is the words it speaks).

- The server implements MCP protocol `2025-06-18`; it does not negotiate older contracts.
- Not frozen before `package:parlance` 1.0: what it shows may still change.
