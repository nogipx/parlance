# parlance contract: mcp (§16)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

## 16. Agents

`mcp` serves the registry to agents over MCP (JSON-RPC 2.0, one message a line: stdio, or a socket carrying it so).

A **board** is what the tools work on: `LocalBoard(registry, by: principal)` in the host's process, or `RemoteBoard(client, mirror)` over remote, where the host's session decides the principal. The tools are curated, not one per command:

| Tool | Does |
|---|---|
| `describe` | the commands this principal may call (params as JSON Schema, refs listing their entities, whether it can run now), states, facts, entities (with the JSON Schema of the value one takes, when its meta tells a `type`) |
| `read` | states now: one, by prefix, or all; a state the principal may not read (§6.1 `readers`) is told as such, and left out of the others (so is a fact it may not hear, from `recent_facts`) |
| `call` | a command by name; an `id` makes a retry safe |
| `recent_facts` | the last facts of a name |
| `why` | a state's value, last change (when, on whose behalf), the calls that led to it: `Registry.explain`, told without the wire's ids |

With `commandTools`, each command the principal may call is a tool of its own as well. A host adds its own tools beside these.

A board answers the same here and over remote, and says so where it cannot:

- A read after a call reads what it wrote: `RemoteBoard` waits for its mirror to reach the call's seq (`catchUp`, 2 s); if it does not, reads throw `BoardBehind` until it does.
- While the registry cannot be reached, reads throw `BoardOffline` rather than answer what the mirror last had.
- Every call the tools make has an id; a `timedOut` or `lost` answer tells the agent to call again with it, and that it does not run twice.
- Tool descriptions hold only what changes with the catalog. Whether a command can run now is asked when `describe` runs, never written into a tool's description.

The session asks for the tools once and again after `toolsChanged()` (or when asking failed), and answers each message when it is done: a long call holds no other back.

`parlance-mcp --connect unix:/path | tcp://host/port [--command-tools]` is the board over remote as a stdio server: it reconnects to the host and follows its feed again after a drop; while the host is away it lists no tools.

**On this machine.** `package:parlance/mcp_io.dart` holds `McpSocketServer(path:, tools:, name:, instructions:, log:, onSessions:)`. It serves agents on a Unix socket readable by its owner alone, opening a session per connection, and its `toolsChanged()` reaches every session. It is apart from `mcp.dart` because it needs `dart:io`.

**A host's own tools.** `McpTool.typed(name:, description:, params: RecordShape<P>, run:)` derives the tool's JSON Schema from the shape (§18): field types, `description`s, defaults, `oneOf` for a `UnionShape` with each variant's description, `additionalProperties: false`. `run` gets the arguments checked and typed; what does not pass is the agent's error, by path (`ops.2.frame: missing`). The description says only what a schema cannot: one undo step, how refs work. `jsonSchema(type)` is the same conversion on its own.

