# switchboard contract: registry (§1, §2, §3, §4, §5, §6, §7, §8, §9, §10, §11, §12, §17)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

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
| `object` | `Map` with named fields; unknown ones refused, an optional one given as null left out | fields: type, `optional`, `default`, `description` |
| `map` | `Map` from any text to one type (files by path) | `value`, `maxEntries` |
| `nullable` | null, or a value of `of`: "none" as a value of its own, apart from an empty list | `of` |
| `oneOf` | one of several objects, told apart by the text in field `key` | `key`, `variants` (objects by tag), `descriptions` |
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
StateDescriptor { name, type, key: entity kind?, readers: { selector: allow | deny }?, meta }
```

- A state has exactly one writer: whoever defined it holds the only write handle.
- `readers` say who may read its values over remote and the MCP board, with the selectors of `callers` (§6.2); none means everyone. Its descriptor stays in the catalog for all; `describeFor` lists the states and facts the principal may not read (`unreadable`), `mayRead(principal, name)` tells one. Code in the registry's own process reads every state: readers bound remote participants, not the host.
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
- The owner may give an **availability** check: synchronous, reads committed state, returns nothing or a reason. `whyUnavailable(command)` asks it without calling, so a client can show a button greyed with the reason.

### 6.3 Facts

```
FactDescriptor { name, type, open: bool, readers: { selector: allow | deny }?, meta }
```

- `readers` say who may hear it over remote and the MCP board, as a state's (§6.1).
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

1. **Dedup.** A call whose id was seen within the dedup window returns the result of the first one; it is not run again. Clients retry with the same id. An id stands for one call: the same id with another command, params or principal is refused (`idConflict`), never answered another call's result.
2. **Lookup.** Unknown command → `unknownCommand`.
3. **Params.** Checked and filled with defaults → `invalidParams`.
4. **Policy.** `callers` for the principal → `notPermitted`.
5. **Availability.** The owner's check → `unavailable`.
6. **Guards.** Every guard (§10) is asked; the first denial → `denied` with the guard's id and reason. A denial marked overridable lets the call through when `override` is set and the principal's kind is one the host allows to override; the call record says it was overridden.
7. **Before hooks.** For interceptable commands, the hooks (§11) run one by one.
8. **Handler.** Gets the call (id, params, cause), bounded by the deadline → `timedOut`; a throw → `failed`; a result that does not pass `returns` → `failed`. **`timedOut` is not an end**: it means no answer came within the deadline. The handler is told (`call.expired`) and may stop; if it goes on, what it does stands, its end is published as a second call record marked `late`, and a retry with the call's id answers that end.
9. **Sets.** A successful explicit setter call updates the base and clears layers (§8).

`CallResult<R>` is `done(value)` (the only end that carries an answer, of type `R` for a typed call, §18) or `refused(code, reason, guard?)`, `failed(error)`, `timedOut`, or `lost(id, reason)`: the answer did not come back over remote (§14), so whether it ran is unknown; a retry with the id runs it at most once. Every finished call is published as a **call record** (request, cause, stages passed, result, override, timings) on the calls stream, for journals.

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
- The registry retains the last ticks by count (default 1000) and the last facts per name (default 100) for `recent(name, n)`. `explain` says when what it cannot find may be forgotten: `forgotten` (the last change), `trailCut` (earlier calls). `describe` tells the dedup window (`dedupWindowMs`): how long an id answers its first result.

## 17. Versions

`describe` over remote carries the protocol version (now 2: calls answer their seq, `recent` was added); the registry's own `describe` does not. Exported layers, own states and link definitions carry a format version; the importer refuses a newer major version and migrates older ones.

## 18. Typed words

The registry keeps names and JSON, as links, remote and agents see it. A host names its words once, with their Dart types, and works through them; nothing else in its code types a name or a param key.

- **Words.** `StateWord<T>` (name, shape, key kind), `CommandWord<P, R>` (name, params as a `RecordShape<P>`, answer as a `Shape<R>` or none, then `R` is `void`), `FactWord<T>` (name, shape). A host's enum of its words implements them; each value carries its own types (`enum ScenesCommand<P, R> implements CommandWord<P, R> { show<({String scene}), void>(...) }`).
- **Shapes** say how a JSON value is a Dart one, and give the registry its type: `Plain(BoolType())` is a `Shape<bool>` (the value type's own Dart type: `ValueType<T>`), `EnumShape(values)` a Dart enum kept as its name, `ListShape(item)`, `RecordShape(fields, to:, from:)` an object as a record, its field names written beside the fields and nowhere else. `RecordShape.none` is the params of a command that takes none.
- **More shapes:** `Nullable(shape)` for null or a value (a state whose "none" means something, such as every app), `MapShape(value)` for a map from text, and `UnionShape(key, {tag: RecordShape}, tagOf:, descriptions:)` for one of several objects as a sealed class. `Part(description:)` describes a field.
- **Through the registry.** `state(word)` defines (`StateWriterOf<T>`), reads, watches; `command(word)` defines with a handler that gets typed params (`CommandCallOf<P>`) and returns `R`, and calls with `P`, answering `CallResult<R>`; `fact(word)` defines (`FactEmitterOf<T>`), streams and lists `Fact<T>`. Refusals, failures, `timedOut` and `lost` are `CallResult<Never>`, so they end a call of any answer type.
- **The word fixes the types.** A call is made on what `command(word)` gives, never by a generic function taking a word and params together: Dart's generics are covariant, so such a function would infer a common supertype of two different records and compile a call with another command's params.
- An answer that does not decode as the word says is `failed`. Names and keys of entity kinds stay strings, and so do references in link params (`$trigger.…`).

