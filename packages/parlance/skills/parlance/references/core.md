# parlance contract: core (§21)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

The core is what the registry stands on, inside the package: typed values in one process, no names, no JSON, no principals, no dependencies but `dart:`. It is not a library of its own; an app takes words and a `Host` (a small one `HostLimits.light`). The registry (§1–12) is built on it, and remote and views on the registry. Nothing above writes a value, emits or serves a command any other way. Nothing of it is seen outside (§21.6).

Its parts are the package's words, local: a `LocalState` is a state, a `LocalCommand` a command, a `LocalFact` a fact, the same as the registry's without names, principals or JSON.

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

None: the core is the registry's alone, and nothing outside the package takes its handles. What a part reads, writes, calls and hears it does through its words (§23).
