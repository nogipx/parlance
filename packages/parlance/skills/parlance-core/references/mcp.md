# parlance contract: mcp (§16)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

## 16. Agents

The package `parlance_mcp` serves the registry to agents over MCP (a consumer of the words, not a part of their language) (JSON-RPC 2.0, one message a line: stdio, or a socket carrying it so).

**An agent is a participant** (§22): the tools work on its `IParticipant`, `parlanceTools(p)`, made by `main` in the host's process (`host.participant(agent)`) or joined across a connection (`Host.join`, where the host's session decides the principal). The tools are curated, not one per command. MCP implements only protocol `2025-06-18`:

| Tool | Does |
|---|---|
| `targets` | published target instances, grouped by vocabulary; optional vocabulary or portable word filter |
| `describe` | the commands this principal may call (params as structural JSON Schema, whether it can run now), states and facts; domain entity lists are read or queried through ordinary words |
| `read` | states now: one, by prefix, or all; a state the principal may not read (§6.1 `readers`) is told as such, and left out of the others (so is a fact it may not hear, from `recent_facts`) |
| `call` | a command by name; an `id` makes a retry safe |
| `recent_facts` | the last facts of a name, from 1 to 100 of them, whatever count the agent gives |
| `why` | a state explanation with mixed journal trails and explicit gaps, or inspection of a call made or served by this participant |

With `commandTools`, each command the principal may call is a tool of its own as well, named by an injective base64url encoding of its full address, prefixed by `p_`; one whose tool name is taken (by a curated tool or another command) or longer than 64 has none, and is called by `call`. A host adds its own tools beside these.

They answer the same here and across a connection, and say so where they cannot:

- A read after a call reads what it wrote: a participant's call answers once its view has reached what the call wrote (§14).
- A state is read by name (`fetch`, §20): across a connection the participant keeps it from then on, so the next read answers at once; it counts as the agent's use of the word (§6.8).
- While the registry cannot be reached (`synced` false), `read` says so rather than answer what was there last.
- Every call the tools make has an id; a `timedOut` or `lost` answer tells the agent to call again with it, and that it does not run twice.
- Tool descriptions hold only what changes with the catalog. Whether a command can run now is asked when `describe` runs, never written into a tool's description.

The session asks for the tools once and again after `toolsChanged()` (or when asking failed), and answers each message when it is done: a long call holds no other back.

`parlance-mcp --connect unix:/path | tcp://host/port [--command-tools]` (the package's binary, which alone takes `rpc_dart_socket`) is an agent's participant across a connection as a stdio server: it joins the host, and joins again after a drop. Started before the host, it lists no tools, and tells the agent they changed once it joins; after a drop it keeps the tools it listed, and what they do answers that the host is not reachable now.

**On this machine.** `package:parlance_mcp/io.dart` holds `McpSocketServer(path:, tools:, name:, instructions:, log:, onSessions:)`. It serves agents on a Unix socket readable by its owner alone (`start` fails rather than serve one it could not make so), opening a session per connection, and its `toolsChanged()` reaches every session. It is apart from `parlance_mcp.dart` because it needs `dart:io`.

**A host's own tools.** `McpTool.typed(name:, description:, params: RecordShape<P>, run:)` derives the tool's JSON Schema from the shape (§18): field types, `description`s, defaults, `oneOf` for a `UnionShape` with each variant's description, `additionalProperties: false`. `run` gets the arguments checked and typed; what does not pass is the agent's error, by path (`ops.2.frame: missing`). The description says only what a schema cannot: one undo step, how refs work. `jsonSchema(type)` is the same conversion on its own.


### Target addressing

`targets` lists actual instances by optional `vocabulary` or `word` name.
`describe` includes `target` and portable `word` alongside each full `name`.
Curated `call`, `read`, `recent_facts` and `why` consume that full name verbatim.
There is no implicit target selection. Optional command tool names use an
injective base64url encoding of the full address, prefixed by `p_`; addresses
that exceed MCP's name length stay accessible through the curated `call` tool.


Host access overrides affect describe, targets, read and call immediately. Warn
is an allowed interaction with a developer diagnostic at the host; describe retains
access: warn as metadata. Inspection itself produces no warning. Command tool lists
follow the existing toolsChanged notification contract when a host caches them.

For causal inspection, recording coverage and bounded diagnostic retention, see [diagnostics.md](diagnostics.md).

`why` accepts either `state` (optional `key` and `historyCount`, 0–100) or `call`. Call inspection is restricted to calls made or served by its participant. State explanations include mixed message trails and explicit gaps.

Parlance call tools return their caller ID as `structuredContent.call`, including
automatically generated IDs, so `why(call: id)` can inspect admission decisions
and completion after the tool returns. The primary text still carries the answer.
