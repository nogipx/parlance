# parlance contract: core (§21)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

The core is the level everything else stands on: typed values in one process, no names, no JSON, no principals, no dependencies but `dart:`. A small task takes it alone (`package:parlance/core.dart`); the registry (§1–12) is built on it, and links, remote, the MCP board and views on the registry. Nothing above writes a value, emits or serves a command any other way.

## 21.1 Hub

A hub commits the writes of its cells and the emits of its signals in **ticks**.

- A write or emit outside a batch is a tick of its own. `batch(fn)` runs `fn` synchronously and commits everything it wrote as one tick; batches nest, the outermost commits; a batch that returns a future is refused.
- Inside a batch (and while a tick is being committed), reads see the batch's own writes; `has` sees only committed values.
- On commit, a write that leaves a value equal to the one there is, and a remove of a value there is not, are dropped. Each remaining change, then each emit, gets the next **seq** of the hub.
- A tick is `HubTick { from, to, changes, emits }`; a change says its store, key, value, previous value, whether it removed, and the **tag** its writer gave. The hub never reads a tag: it is how a layer above carries its own data through (the registry carries the cause and a fact's id).
- `onCommit`, given when the hub is made, sees every tick synchronously, before the `ticks` stream delivers it asynchronously, in seq order.
- A cell or signal made without a hub has one of its own.

## 21.2 Cells

A `Cell<V>` holds one value; a `KeyedCell<K, V>` one value per key.

- **One writer.** `claim()` gives the only write handle; another claim fails until it is released (`dispose`). A released writer cannot write; the values stay.
- **Equality** is `==` unless the cell is made with `equals` (the registry gives deep JSON equality).
- `watch` gives the value now (null when there is none), then every committed change, a remove as null.
- `close()` drops the writes of the cell waiting in a batch, and lets no one claim it again.

## 21.3 Signals

A `Signal<T>` is said once and keeps no value.

- One emitter (`claim()`), or as many as claim it when the signal is **open**.
- An emit is committed in the hub's tick, after the changes, and reaches `stream`.
- `close()` drops its waiting emits and refuses new emitters; an emitter of a closed signal cannot emit.

## 21.4 Ports

A `Port<P, R>` is asked and answers.

- **One handler.** `serve(handler)` fails while another serves it; disposing the returned handle stops serving.
- `call(params)` answers what the handler answers; a handler that throws, or no handler, fails the call. Policy, deadlines and records are not the port's: the registry's call (§9) does them, then asks the port.

## 21.5 What the registry keeps on it

| Registry | Core |
|---|---|
| a state's values | a `KeyedCell<String?, Object?>` (null key for an unkeyed state), deep JSON equality, the registry its only writer |
| `batch`, seq, ticks | one hub; `onCommit` turns a `HubTick` into a `Tick` with names, ids, causes and the time |
| a fact | a `Signal<Object?>`, open as the fact is; the tag is its id and cause |
| a command's handler | a `Port<CommandCall, Object?>`; the stages of §9 run before it is asked |

## 21.6 Interfaces

The core speaks the package's words too: a cell holds a **state**, a port serves a **command**, a signal carries a **fact**; they are the same states, commands and facts without names, principals or JSON. What a participant does with them is five interfaces, named in those words, and the registry's typed handles (§18) are them as well. Code that only reads and writes states, calls commands and says and hears facts takes the interfaces; moving it from the core to the registry changes only where they are made.

| Interface | Core | Registry |
|---|---|---|
| `IStateReader<V>`: `value`, `has`, `watch()` | `Cell`, `KeyedCell.at(key)` | `StateOf.reader(key:)` |
| `IStateWriter<V>`: `set`, `remove` | `CellWriter`, `KeyedCellWriter.at(key)` | `StateWriterOf` (unkeyed), `StateWriterOf.at(key)` |
| `ICommandCaller<P, R>`: `call` | `Port` | `CommandOf.caller(by:)` |
| `IFactEmitter<T>`: `emit` | `SignalEmitter` | `FactEmitterOf` |
| `IFactListener<T>`: `stream` | `Signal` | `FactOf.listener` |

- Through an interface, writes and calls carry no cause: a write starts a new chain on behalf of the writer, a call acts for the principal its `caller` was made for. A handler that must pass `call.causeFor(...)` uses the typed handle itself.
- A call through `caller` answers the value of a done call; any other end fails with `CallNotDone`, which carries the `CallResult`.
