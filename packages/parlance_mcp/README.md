# parlance_mcp

**A host's parlance for agents over stdio, reached over a Unix socket or
TCP.**

[parlance](https://pub.dev/packages/parlance) gives every part of an app a
shared language of states, commands, queries and facts. This package speaks
that language with an AI agent: it serves the words of a running host as
curated [MCP](https://modelcontextprotocol.io) tools, so an agent reads what
is so, calls commands and hears facts like any other part.

The transport between the agent-facing stdio server and the host is a Unix
socket or TCP; the agent never knows the difference.

## Run

```sh
dart pub global activate parlance_mcp
parlance-mcp --help
```

A whole small host with an agent's vocabulary:
[`example/`](https://github.com/nogipx/parlance/tree/main/packages/parlance_mcp/example)
(`example/agent.dart` runs one, `example/notes.dart` is the words it speaks).

- Not frozen before `package:parlance` 1.0: what it shows may still change.
