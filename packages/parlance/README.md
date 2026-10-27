# parlance

**A shared language for the parts of an app that should not know each other.**

A screen, a sound module, a plugin, a phone on the network, an AI agent. Keeping such parts apart is nothing new: interfaces, dependency injection, an event bus. But each of those draws the line its own way, pair by pair, and leaves the rest to every team: who owns a value, who may change it, why it changed, how a part outside the process joins in.

parlance draws the line once, as a language. The parts speak a common vocabulary; each knows the words, never who stands behind them, and ownership, rights and causes come with the language rather than with each pair. *Parlance* is the way of speaking used in a particular place; here, the place is your app.

## The words

A vocabulary is made of **words**: a name and a type. There are three kinds, like parts of speech:

| Kind | Means | Example | You |
| --- | --- | --- | --- |
| **state** | what is so now | `audio.muted`, `scene.current` | read and watch it; only its owner writes it |
| **command** | a request to do something | `audio.mute`, `scene.show` | call it; exactly one handler answers |
| **fact** | what happened | `chat.message`, `stream.started` | hear it; nothing is kept after it is said |

A command that only answers is a **query** (`orders.page`, `catalog.search`): a question by params that no state holds. It changes nothing, so it is safe to ask again, and the registry keeps nothing of it.

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

- **Who speaks.** Every write and call is made by a principal (`user/local`, `plugin/hydra`, `viewer/twitch/123`), and every command says who may call it. A refusal says why: not permitted, unavailable now, denied by a guard.
- **Why it is so.** Every change carries its cause: who acted and the call it answered. The same causes make the traces: with a log, every call is a span, the calls it led to its children, across the network too. `explain('audio.muted')` answers *"the mixer wrote it, answering `audio.mute` that a viewer called"*.
- **Words are a public API.** Plugins, agents and the calls a host stores name them, so a renamed word keeps its old name as an alias and nothing that named it breaks.

## Small and large, one language

| Level | Library | What you get |
| --- | --- | --- |
| core | `core.dart` | States, commands and facts without names: a `Cell` holds a state, a `Port` serves a command, a `Signal` carries a fact. One writer per state, the value replayed to every new listener, changes committed together in ticks. Typed, in one process, no dependencies. For two parts of an app that need to talk. |
| registry | `registry.dart` | The named vocabulary built on the core: a catalog, typed words, who may call what, causes, guards, and a feed of every change. |
| participants | `participant.dart` | A part of the app sees the registry only as one principal and defines words only in its namespaces; `main` hands each its participant, so who may call and read what holds in the process too. |
| over the network | `remote.dart`, `view.dart` | The same vocabulary over rpc_dart: a remote part reads, calls and even owns words, and sees only what its rights allow. |
| agents | `mcp.dart`, `parlance-mcp` | Curated MCP tools, so an AI agent speaks the vocabulary too. |

What a part does with the words is the same five interfaces at every level: `IStateReader`, `IStateWriter`, `ICommandCaller`, `IFactEmitter`, `IFactListener`. Code written on them moves from the core to the registry unchanged; only the place where things are made changes.

## In short

One way for every part to say what it has, what it can be asked and what happened to it, whether it sits in the same process, across the network or in an agent, and one record of who asked, whether they were allowed, and why the world is as it is now.

- Every level in a few lines, one domain throughout: [`example/levels/`](example/levels/).
- A whole host in miniature: [`example/`](example/) (`dart run example/main.dart`).
- The contract the code follows, section by section: [`skills/parlance/references/`](skills/parlance/references/).
