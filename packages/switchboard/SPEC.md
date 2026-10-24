# switchboard — specification

Version 0.1 (draft). The design and its reasons are in `docs/Tephra — словарь и связи.md`; this file is the contract the code and its tests follow. Where they disagree, this file is fixed first, then the code.

switchboard is three libraries in one package, with no domain words in any of them (a test checks):

- `registry` — the vocabulary (states, commands, facts), layers, the guard and before points, the feed.
- `links` — the user's own words and the four links (reaction, binding, constraint, interception), built only on the public API of `registry`.
- `remote` — the registry over `rpc_dart` for other processes.

Imports go one way: `links` and `remote` import `registry`, never each other; only `remote` imports `rpc_dart`.

## 1. Values and names

**Values** are JSON values: `null`, `bool`, `num`, `String`, `List`, `Map<String, Object?>`. Everything a registry holds or sends is a value, so it crosses a process boundary and is persisted without codecs. Values are deep-frozen when they enter the registry. Equality is deep.

**Names** are dotted lower-case words: `^[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)*$`. The first word is the owner's namespace by convention; the registry does not enforce ownership by name, only by handle.

**Keys** (of keyed states) are entity ids: non-empty strings.

## 2. Types

A type checks a value and fills defaults. Types are values themselves (they serialize to JSON for `describe`).

| Type | Value | Options |
|---|---|---|
| `bool` | `bool` | |
| `int` | `int` | `min`, `max` |
| `num` | `num` | `min`, `max` |
| `text` | `String` | `maxLength` |
| `enum` | one of the given strings | `values` |
| `duration` | `int`, milliseconds, ≥ 0 | `max` |
| `ref` | entity id `String` | `kind` |
| `list` | `List` of one type | `item`, `maxItems` |
| `object` | `Map` with named fields | fields: type, `optional`, `default` |
| `custom` | anything the host's checker accepts | `name` |
| `any` | any value | |

- `ref` is valid when the host registered the kind and the kind contains the id at the time of the check.
- `object` rejects unknown fields, fills missing optional fields with their default (or leaves them out when there is none), and rejects missing required fields.
- `custom` types are registered by the host: a name and a checker. The package never interprets them.

## 3. Entity kinds

The host registers entity kinds: a name and a function listing the current entities (`id`, `label`). The registry uses them to check `ref` values and to answer `describe`. When the entities of a kind change, the host says so (`entitiesChanged`); the registry passes it on in its catalog changes.

## 4. Principals and causes

A **principal** is who acts: a `kind` and an `id` (`user:local`, `plugin:hydra`, `viewer:twitch:123`). Kinds are an open set declared by the host. The package reserves two: `system` (the registry itself) and `link` (the links engine).

A **cause** is why something happens:

```
Cause { by: Principal, parent: message id?, chain: [link or hook ids], test: bool }
```

- Every message carries a cause.
- Causes are passed explicitly, never through zones. A handler gets its call and takes `call.causeFor(by)` for what it does: nested calls, writes, facts. Its `parent` is the call; `chain` and `test` carry over. A before hook gets the cause for its own calls as an argument. A write or call without a cause starts a new chain on behalf of whoever acts.
- An owner that writes without the call's cause still works, but loses the trail: the journal cannot tell why, and a layer recognises the write as its echo only by the value (§8).
- `chain` is how loops are found: a link or hook never runs for a message whose chain already holds its id.
- `test` marks everything a trial run caused; consumers may show it differently.

## 5. Messages, sequence and epoch

- Every message has an **id**: 128 random bits as 32 hex digits, unless the sender gives its own.
- A registry has an **epoch**: an id made when it starts. Sequence numbers are only comparable within one epoch; a client that sees a new epoch starts over from a snapshot.
- Every committed state change and fact gets the next **sequence number** (`seq`) of the epoch. Within a registry, seq is a total order consistent with causality.

## 6. Vocabulary

### 6.1 States

```
StateDescriptor { name, type, key: entity kind?, meta }
```

- A state has exactly one writer: whoever defined it holds the only write handle.
- A keyed state holds one value per key; an unkeyed state holds one value.
- Reading gives the last committed value, or nothing when there is none.
- Removing a key or the whole state is a change like any other.

### 6.2 Commands

```
CommandDescriptor {
  name, params: object type, returns: type?, owner,
  sets: { state, key: param name?, value: param name }?,
  callers: { selector: allow | warn | deny },
  interceptable: bool, deadline: duration, meta
}
```

- Exactly one handler per command; defining a command registers its handler.
- `sets` says the command sets that state: the target key comes from param `key`, the value from param `value`. A state has at most one setter. Layers (§8) and `flip` need the setter, and call it with only those two params, so its other params must be optional.
- `callers` selectors are a principal kind (`user`), a kind and id (`plugin:hydra`) or `*` for anyone; the most specific selector wins; a principal matched by none is denied. `warn` allows the call; it exists for editors, which tell the author that, for example, any viewer can now do this.
- `deadline` bounds the handler; the default is 30 s.
- The owner may give an **availability** check: synchronous, reads committed state, returns nothing or a reason.

### 6.3 Facts

```
FactDescriptor { name, type, open: bool, meta }
```

- The definer holds an emit handle. When `open`, the host may hand more emit handles for the same fact to other producers (the chat of several platforms).
- A fact has an id. A fact whose id was already seen within the dedup window is dropped: producers may retry.

### 6.4 Catalog

Descriptors come and go at runtime (a plugin starts or stops). The catalog is the current set of descriptors and entity kinds; every addition, removal and `entitiesChanged` is a catalog change with its own stream. Removing a command fails the calls waiting in its before stage with `unknownCommand`; a running handler finishes.

## 7. Ticks

A **tick** is the unit of change: every state write and fact made in it is committed together.

- A write or emit outside a batch is a tick of its own. `batch(fn)` runs `fn` synchronously and commits everything it wrote as one tick. Batches nest; the outermost one commits.
- Inside a batch, reads see the batch's own writes (read your writes); everyone else sees nothing until the commit.
- On commit, writes that leave a value unchanged are dropped; each remaining change and each fact gets its seq; the tick is delivered as one message: `Tick { epoch, from, to, changes, facts }`.
- Delivery is asynchronous and in seq order. A subscriber that throws does not stop the others; the error goes to the host's error sink.
- Observers (links, conditions, the remote feed) evaluate per tick, never in the middle of one: two states the owner changed together are never seen half-changed.

## 8. Layers

A layer is a lease on a state value: "while I hold this, the value is X".

```
pushLayer(state, key?, value, owner: { id, by: Principal }, priority = 0, ttl?) → handle
```

- The state must have a setter. The layer's value must pass the state's type.
- **Effective value**: the value of the top layer: the highest priority, among equals the latest pushed. Without layers, the **base**.
- **Base**: captured from the committed value when the first layer on the target is pushed.
- When the effective value changes, the registry calls the setter with it, on behalf of the top layer's principal (so policy and guards apply), with the layer's owner in the cause chain. This is a **layer dispatch**.
- When the last layer goes, the registry dispatches the base, if there is one and it differs from the current value.
- **An explicit set clears layers.** A setter call that is not a layer dispatch and succeeds makes its value the new base and drops every layer on the target. So does a committed change of the state that is not an echo of a layer dispatch (its cause is not a dispatch for this target) and differs from the effective value. Dropped layers are reported to their owners (`dropped: overridden`).
- A refused layer dispatch keeps the layer and reports `refused` with the reason.
- `ttl` drops the layer after that long (`dropped: expired`).
- Layers survive restarts as leases: `exportLayers()` gives their owners, values, priorities, bases and absolute expiry; `importLayers()` restores them **unclaimed**. An owner reclaims its layers with `claim(ownerId)` within the grace period (default 30 s); unclaimed layers are dropped (`dropped: unclaimed`), expired ones are dropped on import.

## 9. Calls

```
call(name, params, by: Principal, id?, override = false) → CallResult
```

A call goes through these stages, in order; the first refusal ends it:

1. **Dedup.** A call whose id was seen within the dedup window returns the result of the first one; it is not run again. Clients retry with the same id.
2. **Lookup.** Unknown command → `unknownCommand`.
3. **Params.** Checked and filled with defaults → `invalidParams`.
4. **Policy.** `callers` for the principal → `notPermitted`.
5. **Availability.** The owner's check → `unavailable`.
6. **Guards.** Every guard (§10) is asked; the first denial → `denied` with the guard's id and reason. A denial marked overridable lets the call through when `override` is set and the principal's kind is one the host allows to override; the call record says it was overridden.
7. **Before hooks.** For interceptable commands, the hooks (§11) run one by one.
8. **Handler.** Gets the call (id, params, cause), bounded by the deadline → `timedOut`; a throw → `failed`; a result that does not pass `returns` → `failed`.
9. **Sets.** A successful explicit setter call updates the base and clears layers (§8).

`CallResult` is `done(value)` or `refused(code, reason, guard?)`, `failed(error)`, `timedOut`. Every finished call is published as a **call record** (request, cause, stages passed, result, override, timings) on the calls stream, for journals.

## 10. Guards

```
addGuard(id, check, overridable = true) → handle
```

- `check` is synchronous, reads committed state only, makes no calls, and returns nothing or a denial reason.
- Guards are asked for every call that reached stage 6, layer dispatches included.
- A guard that throws counts as no denial; the error goes to the error sink.

## 11. Before hooks

```
addBefore(command, id, run, priority = 0, timeout) → handle
```

- Only for interceptable commands; `timeout` is required.
- Hooks run one at a time, highest priority first. `run` is asynchronous and may make calls; those calls carry the hook's id in their chain, so the same hook never intercepts them.
- A hook that times out or throws is abandoned; the call goes on. A hook cannot cancel the call or change its params: that is what guards are for.
- **Hurry.** While a call is in its before stage, a new call of the same command with equal params from a principal allowed to override skips the remaining hooks of the waiting call and receives its result; it is not run twice.

## 12. The feed

Remote clients and journals read the registry as a feed:

```
feed(since?: (epoch, seq)) → Snapshot? then Tick, Tick, …
```

- Without `since`, or with another epoch, or with a seq older than the retained ticks: first a **snapshot** (every state value, the catalog, the epoch and seq), then live ticks. A snapshot after a gap says `factsLost: true`.
- With a seq still retained: the retained ticks after it, then live ticks, with no gap and no repeat.
- The registry retains the last ticks by count (default 1000) and the last facts per name (default 100) for `recent(name, n)`.

## 13. Links

Links are data. The engine validates them against the catalog; a link that names something the catalog lacks is **unresolved** and inactive until the catalog has it (a plugin may start later).

### 13.1 Own words

- **Own command** `my.<name>`: params, steps, callers (default: every kind but `system`). Registered as a command whose handler runs the steps on behalf of `link:<id>`.
- **Own state** `my.<name>`: `bool` or `enum`, with a default and a setter `my.<name>.set { value }`. Its values are the engine's to persist.

### 13.2 Triggers

| Kind | Fires |
|---|---|
| `fact` | a fact with the name, whose payload matches the filter |
| `state` | a state (and key) `becomes` / `leaves` a value, or `changes` (optionally `from` → `to`); `for` — and stays so that long |
| `every` | every interval, from when the link activates |
| `at` | at a local time of day, on the given weekdays |
| `manual` | `links.press { link }`; the presser is the principal |

Options on any trigger: `throttle` — at most once per interval, per key (a path into the trigger, e.g. the viewer); `once` — once until `links.reset { link }`. The host registers **trigger extensions**: a name, a translation to one of the kinds above, and a parse of the extension's own options; the package knows none.

The principal of a run is the presser for `manual`, the principal an extension gives (a viewer, for a chat command), else `link:<id>`: facts, states, time, own commands and interceptions run on behalf of the link.

### 13.3 Conditions

Over committed state only: `is`, `not`, `in`, `<`, `<=`, `>`, `>=`; a list means all, `any` means at least one. No facts, no branches.

The engine keeps its own view of the state, built by applying ticks in seq order. Conditions of triggers, bindings and waits read the view **as of the tick being handled**, never state committed after it: a fact is judged by the state at its position in the log. A press reads the registry at the time of the press; constraints read it at the time of the call; steps read it when they run.

### 13.4 Steps

`call` (a command, own ones too), `flip` (a bool state through its setter), `wait`, `waitUntil` (a fact or a condition, with a timeout; on timeout the run stops unless `orContinue`), `temporarily` (calls whose commands have `sets` become layers for `for` or `until`; other calls run once).

Params are values, references (`$trigger.<path>`, `$state.<name>[<key>]`) and string templates (`"{from} raided"`). No arithmetic, variables or `if`.

### 13.5 Reactions

Trigger(s) → conditions → steps. Mode when it fires while running: `single` (skip; default), `restart` (cancel the running one, its layers drop), `queue` (with a limit; default 10). A run lasts until its steps and its temporaries end. A refusal stops the run unless the step says `orContinue`.

### 13.6 Bindings

While the conditions hold, push one layer per held call (only commands with `sets`), owner `link:<id>`, with the link's priority; when they stop, drop them. A binding whose layer was dropped as `overridden` does not push it again until its conditions turn false and then true. An **anchor** gives a binding its condition and its home: the host registers anchor kinds (an entity kind and the condition an entity makes); the binding names the entity.

### 13.7 Constraints

A guard: a target (a command with a param filter, every command of a namespace, or every command), the principals it applies to (default: everyone), conditions, the principals it applies to, a reason. Overridable unless it says otherwise.

### 13.8 Interceptions

A before hook on an interceptable command: steps, a priority and a required timeout.

### 13.9 Safety

- Loops: a link never fires for a message whose chain holds its id.
- Rate: a link that fires more than 20 times a minute is disabled and the engine emits `links.disabled { link, reason }`.
- Time: the registry reads time from its `clock` (given, or the zone's clock when it was made) and waits with `Timer`, so tests run time by hand with `fake_async`.
- Trials: `links.try { link }` runs a reaction with a made-up trigger, or checks a constraint, with `test` set in the cause.

## 14. Remote

The service `Switchboard`, generated by `rpc_dart_generator` from one annotated interface (`lib/src/remote/contract.dart`); every method has codecs, so it runs over any transport.

| Method | Kind | Does |
|---|---|---|
| `describe` | unary | the catalog, epoch, seq and protocol version |
| `feed(epoch?, since?)` | server stream | the catalog first and on every catalog change, then the feed of §12 |
| `call(id, command, params, override, test)` | unary | a call on behalf of the session's principal |
| `pushLayer(state, key?, value, priority, ttl?)` | unary | a layer held by the session |
| `popLayer(layer)` | unary | drops a layer of the session |
| `layerEvents` | server stream | what happens to the session's layers |

- **A session is one connection with one principal**, fixed by the host when it accepts the connection: the host makes a `RegistryResponder(registry, principal: …)` per connection and `close()`s it when the connection ends. The layers the session pushed go with it; its calls are refused after.
- **A call's result is data, not an error.** `done`, `refused` (with the code, the reason, the guard and whether it is overridable), `failed`, `timedOut` travel as the reply, because a refusal is a normal answer and carries more than a status code. rpc_dart statuses are for the session's own errors: `notFound` (no such state or layer), `invalidArgument` (a value of the wrong type), `permissionDenied` (the principal may not set that state), `failedPrecondition` (a state without a setter), `unavailable` (the session ended).
- **Ids are per principal.** The registry sees a call's id as `<principal>/<id>`: a client that lost its connection retries with the same id and gets the first result; another principal reusing the id does not.
- **`test`** is the only part of a cause a client may set; the chain and the parent are the registry's.
- **The mirror** (`RegistryMirror`) keeps a participant's copy of the states from the feed and, given a new client after a lost connection, resumes after the seq it has; a gap sends it back to a snapshot.

## 15. Versions

`describe` carries the protocol version. Exported layers, own states and link definitions carry a format version; the importer refuses a newer major version and migrates older ones.
