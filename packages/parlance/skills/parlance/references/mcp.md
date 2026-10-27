# parlance contract: mcp (§16)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

## 16. Agents

`mcp` serves the registry to agents over MCP (JSON-RPC 2.0, one message a line: stdio, or a socket carrying it so).

**An agent is a participant** (§22): the tools work on its `IParticipant`, `parlanceTools(p)`, made by `main` in the host's process (`registry.participant(agent)`) or joined across a connection (`RemoteParticipant.join`, where the host's session decides the principal). The tools are curated, not one per command:

| Tool | Does |
|---|---|
| `describe` | the commands this principal may call (params as JSON Schema, refs listing their entities, whether it can run now), states, facts, entities (with the JSON Schema of the value one takes, when its meta tells a `type`) |
| `read` | states now: one, by prefix, or all; a state the principal may not read (§6.1 `readers`) is told as such, and left out of the others (so is a fact it may not hear, from `recent_facts`) |
| `call` | a command by name; an `id` makes a retry safe |
| `recent_facts` | the last facts of a name |
| `why` | a state's value, last change (when, on whose behalf), the calls that led to it: `Registry.explain`, told without the wire's ids |

With `commandTools`, each command the principal may call is a tool of its own as well. A host adds its own tools beside these.

They answer the same here and across a connection, and say so where they cannot:

- A read after a call reads what it wrote: a participant's call answers once its view has reached what the call wrote (§14).
- A state is read by name (`fetch`, §20): across a connection the participant keeps it from then on, so the next read answers at once; it counts as the agent's use of the word (§6.8).
- While the registry cannot be reached (`synced` false), `read` says so rather than answer what was there last.
- Every call the tools make has an id; a `timedOut` or `lost` answer tells the agent to call again with it, and that it does not run twice.
- Tool descriptions hold only what changes with the catalog. Whether a command can run now is asked when `describe` runs, never written into a tool's description.

The session asks for the tools once and again after `toolsChanged()` (or when asking failed), and answers each message when it is done: a long call holds no other back.

`parlance-mcp --connect unix:/path | tcp://host/port [--command-tools]` is an agent's participant across a connection as a stdio server: it joins the host, joins again after a drop, and lists no tools while the host is away.

**On this machine.** `package:parlance/mcp_io.dart` holds `McpSocketServer(path:, tools:, name:, instructions:, log:, onSessions:)`. It serves agents on a Unix socket readable by its owner alone, opening a session per connection, and its `toolsChanged()` reaches every session. It is apart from `mcp.dart` because it needs `dart:io`.

**A host's own tools.** `McpTool.typed(name:, description:, params: RecordShape<P>, run:)` derives the tool's JSON Schema from the shape (§18): field types, `description`s, defaults, `oneOf` for a `UnionShape` with each variant's description, `additionalProperties: false`. `run` gets the arguments checked and typed; what does not pass is the agent's error, by path (`ops.2.frame: missing`). The description says only what a schema cannot: one undo step, how refs work. `jsonSchema(type)` is the same conversion on its own.

