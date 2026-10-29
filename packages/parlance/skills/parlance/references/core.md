# parlance contract: core (§21)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

The core is the level everything else stands on: typed values in one process, no names, no JSON, no principals, no dependencies but `dart:`. A small task takes it alone (`package:parlance/core.dart`); the registry (§1–12) is built on it, and remote, the MCP tools and views on the registry. Nothing above writes a value, emits or serves a command any other way.

It is the level under both registries; a small app that wants owners, words and rules but no history starts on a `LocalRegistry` (§22.5) rather than here, and moves to a `Registry` by changing `main`. Its parts are the package's words, local: a `LocalState` is a state, a `LocalCommand` a command, a `LocalFact` a fact, the same as the registry's without names, principals or JSON; `Local` says they live in this process, as a `LocalParticipant` and a `LocalView` do. A part that starts on them moves to the registry's words keeping its code (§21.6).

## 21.1 Local hub

A `LocalHub` commits the writes of its states and the emits of its facts in **ticks**.

- A write or emit outside a batch is a tick of its own. `batch(fn)` runs `fn` synchronously and commits everything it wrote as one tick; batches nest, the outermost commits; one whose body throws commits nothing of it, and what waited before it for a state or fact closed in it stays dropped; a batch that returns a future is refused.
- Inside a batch (and while a tick is being committed), reads see the batch's own writes; `has` sees only committed values.
- On commit, a write that leaves a value equal to the one there is, and a remove of a value there is not, are dropped. Each remaining change, then each emit, gets the next **seq** of the hub.
- A tick is `LocalTick { from, to, changes, facts }`; a change (`LocalStateChange`) says its state, key, value, previous value, whether it removed, and the **tag** its writer gave; an emit (`LocalFactEmit`) its fact, value and tag. The hub never reads a tag: it is how a layer above carries its own data through (the registry carries the cause and a fact's id).
- `onCommit`, given when the hub is made, sees every tick synchronously, before the `ticks` stream delivers it asynchronously, in seq order.
- A state or fact made without a hub has one of its own.

## 21.2 Local states

A `LocalState<V>` holds one value; a `LocalKeyedState<K, V>` one value per key.

- **One writer.** `claim()` gives the only write handle (`LocalStateWriter`, `LocalKeyedStateWriter`); another claim fails until it is released (`dispose`). A released writer cannot write; the values stay.
- **Equality** is `==` unless the state is made with `equals` (the registry gives the word's shape's).
- `watch` gives the value now (null when there is none), then every committed change, a remove as null.
- `close()` drops the writes of the state waiting in a batch, and lets no one claim it again.
- A keyed state's writer `clear()`s it: every committed key is removed, and what the batch running now wrote of it is dropped, so a key written there and never committed leaves nothing.

## 21.3 Local facts

A `LocalFact<T>` is said once and keeps no value.

- One emitter (`claim()`, a `LocalFactEmitter`), or as many as claim it when the fact is **open**.
- An emit is committed in the hub's tick, after the changes, and reaches `stream`.
- `close()` drops its waiting emits and refuses new emitters; an emitter of a closed fact cannot emit.

## 21.4 Local commands

A `LocalCommand<P, R>` is asked and answers.

- **One handler.** `serve(handler)` fails while another serves it; disposing the returned handle stops serving.
- `call(params)` answers what the handler answers; a handler that throws, or no handler, fails the call. Policy, deadlines and records are not the local command's: the registry's call (§9) does them, then asks it.

## 21.5 What the registry keeps on it

| Registry | Core |
|---|---|
| a state's values | a `LocalKeyedState<String?, Object?>` (null key for an unkeyed state) of the values as the word's shape keeps them (§18), its equality the shape's, the registry its only writer |
| `batch`, seq, ticks | one `LocalHub`; `onCommit` turns a `LocalTick` into a `Tick` with names, ids, causes and the time |
| a fact | a `LocalFact<Object?>`, open as the fact is; the tag is its id and cause |
| a command's handler | a `LocalCommand<CommandCall, Object?>`; the stages of §9 run before it is asked |

## 21.6 Interfaces

What a part does with states, commands and facts is five interfaces, named in those words; the core's local ones are them, and so are the registry's typed handles (§18). Code that only reads and writes states, calls commands and says and hears facts takes the interfaces; moving it from the core to the registry changes only where they are made.

| Interface | Core | Registry |
|---|---|---|
| `IStateReader<V>`: `value`, `has`, `watch()` | `LocalState`, `LocalKeyedState.at(key)` | `StateOf.reader(key:)` |
| `IStateWriter<V>`: `set`, `remove` | `LocalStateWriter`, `LocalKeyedStateWriter.at(key)` | `StateWriterOf` (unkeyed), `StateWriterOf.at(key)` |
| `ICommandCaller<P, R>`: `call` | `LocalCommand` | `CommandOf.caller(by:)` |
| `IFactEmitter<T>`: `emit` | `LocalFactEmitter` | `FactEmitterOf` |
| `IFactListener<T>`: `stream` | `LocalFact` | `FactOf.listener` |

- Through an interface, writes and calls carry no cause of their own: in a handler a participant serves they follow from its call; elsewhere a write starts a new chain on behalf of the writer, a call acts for the principal its `caller` was made for.
- A call through `caller` answers the value of a done call; any other end fails with `CallNotDone`, which carries the `CallResult`.
