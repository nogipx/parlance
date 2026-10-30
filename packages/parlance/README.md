# parlance

**A shared language for the parts of an app that should not know each other.**

A screen, a heating module, a plugin, a phone on the network, an AI agent. Keeping such parts apart is nothing new: interfaces, dependency injection, an event bus. But each of those draws the line its own way, pair by pair, and leaves the rest to every team: who owns a value, who may change it, why it changed, how a part outside the process joins in.

parlance draws the line once, as a language. The parts speak a common vocabulary; each knows the words, never who stands behind them, and ownership, rights and causes come with the language rather than with each pair. *Parlance* is the way of speaking used in a particular place; here, the place is your app.

## The words

A vocabulary is made of **words**: a name and a type. There are four kinds, like parts of speech:

| Kind | Means | Example | You |
| --- | --- | --- | --- |
| **state** | what is so now | `house.heat`, `house.light` | read and watch it; only its owner writes it |
| **command** | a request to do something | `house.set_light`, `house.lock` | call it; exactly one handler answers |
| **query** | a question that changes nothing | `orders.page`, `catalog.search` | ask it, again if need be; nothing of it is kept |
| **fact** | what happened | `house.rang`, `house.motion` | hear it; nothing is kept after it is said |

A **query** is a command that only answers: a question by params that no state holds. It changes nothing, so it is safe to ask again, and the registry keeps nothing of it.

| | command | query |
| --- | --- | --- |
| does | changes something: writes, says, calls | only answers |
| asked again with its id | answers the first result, runs once | runs again |
| call record (journal, `explain`) | kept | none: its answers take no memory |
| who may, by default | must be said | as who may read |
| to an agent | an action | safe to ask |
| a write, a fact, a command from its handler | done | refused: the query fails, nothing changed |
| in Dart | `ICommandWord`, `.call(params)` | `IQueryWord`, `.ask(params)` |

Many consumers of one value that changes: a state. One asker's answer to its own params: a query. Anything that changes the world: a command.

Every word has an **owner**, the part that defined it. Nobody changes someone else's state: you ask its owner with a command, and the owner decides what to write. A command says nothing of which states its handler writes; what it wrote is told after, by causes.

Around the words:

- **Who speaks.** Every write and call is made by a principal (`resident/ann`, `module/visit`, `guest/bob`), and every command says who may call it. A refusal says why: not permitted, unavailable now, denied by a guard.
- **Why it is so.** Every change carries its cause: who acted and the call it answered. The same causes make the traces: with a log, every call is a span, the calls it led to its children, across the network too. `explain('house.light')` answers *"the house's devices wrote it, answering `house.set_light` that ann called"*.
- **Words are a public API.** Plugins, agents and the calls a host stores name them, so a renamed word keeps its old name as an alias and nothing that named it breaks.

## One way, small or large

| Piece | Library | What it is |
| --- | --- | --- |
| words | `schema.dart` | A vocabulary written once as an abstract class (`@Vocabulary`); the generator makes its typed words, the base of its owner and its client. What an owner and a part that uses the words see. |
| a host | `app.dart` | What `main` does: a `Host` makes the participants of the app's parts and serves them across connections; another process joins with `Host.join`. A small app is the same `Host` with `HostLimits.light`, keeping nothing past what is now. |
| a test | `testing.dart` | `TestHost`: a `Host` for a test, stand-ins for the modules it leaves out, what happened read back. |
| tools | `tools.dart` | The registry underneath, for tools: a journal, an inspector, a host of guests in another language. Not frozen. |
| agents | the package `parlance_mcp` and its binary `parlance-mcp` | Curated MCP tools, so an AI agent speaks the vocabulary too. |

An owner and the parts that use its words do not know where they run: in the host's process and across a connection they are given the same `IParticipant`.

## In short

One way for every part to say what it has, what it can be asked and what happened to it, whether it sits in the same process, across the network or in an agent, and one record of who asked, whether they were allowed, and why the world is as it is now.

- A whole host in miniature: [`example/`](example/) (`dart run example/main.dart`).
- The contract the code follows, section by section: [`skills/parlance/references/`](skills/parlance/references/).
