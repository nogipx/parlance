# parlance contract: registry (§1, §2, §3, §4, §5, §6, §7, §8, §9, §10, §11, §12, §17)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

**What a host holds.** `main` makes the `Registry`, makes its participants (§22) and watches it; it does nothing on anyone's behalf through it. Exported are its making (its bounds, overriders, clock, log), `participant(...)`, and what only tells: the catalog and its changes, `describe`, `ticks` and `seq`, `calls`, `callStarts`, `running`, `callRecord`, `explain`, `lastChange`, `conversation`, `usesOf`, `usage`; and what is the host's alone to say: `alias` (§6.4), `registerType` (§2), `dispose`. Everything that acts, the sections below describe as the registry's (defining words with `by:`, calling and writing as any principal, guards, kinds, batches, reads, watches and facts by name, status by principal, the feed), is the package's own (`RawRegistry`, and the typed `registry.state(word)` and the rest, §18): participants, sessions and views are built on it, and a part reaches it only as one of them, so no code but the package's can act as someone it is not, or define a word outside a namespace. A test of the package imports it from `src/`.

## 1. Values and names

**Values** are JSON values: `null`, `bool`, `num`, `String`, `List`, `Map<String, Object?>`. Everything a registry holds or sends is a value, so it crosses a process boundary and is persisted without codecs. Values are deep-frozen when they enter the registry. Equality is deep.

**Names** are lower-case words split by `.`, each from a letter, its parts joined by `_` or `-`: `^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)*$` (`audio.voice.muted_talk`, `kitten-daycare.lights`). The two joiners are different signs: `muted-talk` and `muted_talk` are two names; `.` only ever splits; every other sign is reserved. The same holds for namespaces, entity kinds, type names, and what becomes a first word: a plugin's id is the namespace of its words. The first word is the owner's namespace by convention; the registry does not enforce ownership by name, only by handle (participants do, §22.1).

**Versions** are optional and per word. A breaking change to a word that must live beside the old one is a new word, the same name with `.v<N>`: `orders.order.v2` is version 2 of `orders.order`. A name without a version is version 1; `.v1` is refused, and so are `.v0` and leading zeros, so a word has one name, never two spellings. A version is the last word only: `orders.v2.cancel` is refused, so no name reads as a version it is not. `wordVersion(name)` tells the word and the version. Versions are words like any other: each has its type, owner, readers and callers; nothing projects one into another. The owner serves every version it keeps until none is used: a command by a handler per version, a state by writing each version in one batch, a fact by saying each, every one with an id of its own (§6.3). Inside one build the compiler shows what still uses an old version; versions matter at the boundaries that outlive a build (participants across a connection, plugins, stored calls, agents).

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
| `object` | `Map` with named fields; unknown ones refused, an optional one given as null left out (but for a nullable one, where null is its value) | fields: type, `optional`, `default`, `description` |
| `map` | `Map` from any text to one type (files by path) | `value`, `maxEntries` |
| `nullable` | null, or a value of `of`: "none" as a value of its own, apart from an empty list | `of` |
| `oneOf` | one of several objects, told apart by the text in field `key` | `key`, `variants` (objects by tag), `descriptions` |
| `custom` | anything the host's checker accepts | `name` |
| `any` | any value | |

- `ref` is valid when the host registered the kind and the kind contains the id at the time of the check.
- `object` rejects unknown fields, fills missing optional fields with their default (or leaves them out when there is none), and rejects missing required fields.
- `custom` types are registered by the host: a name and a checker. The package never interprets them.

## 3. Entity kinds

The host registers entity kinds: a name and a function listing the current entities (`id`, `label`, and `meta`: what else an editor or an agent needs, such as the type of the value it takes). The registry uses them to check `ref` values and to answer `describe`. When the entities of a kind change, the host says so (`entitiesChanged`); the registry passes it on in its catalog changes.

## 4. Principals and causes

A **principal** is who acts: a `kind` and an `id`. Kinds are an open set declared by the host. The package reserves one: `system` (the registry itself).

**A principal is a path.** Its selector is its kind, then each level of its id after `/`: `user/local`, `plugin/hydra`, `viewer/twitch/123`, `module/orders/sync`. `/` is the only separator and every level is one: the path of a principal tells where it stands, and nothing else does. A level holds letters, digits, `.`, `-` and `_` only, as gRPC names do; every other sign is reserved (`/` and `#` have their uses, the rest are kept for later). A kind (from a letter) and a part's name are ours, as names are: lower-case letters and digits joined by `_` or `-` (`studio/layer_fields`); a level of an id may come from outside, letters, digits, `.`, `-` and `_`, and keeps its case (`UCabc` and `UCAbc` are two channels). A text from outside becomes a level by `Principal.levelOf`, the rule Kubernetes and Helm name things by: one that is a level already stays as it is; else every run of other signs becomes `_` and an FNV-1a hash of the whole text is added after a `.` (`ann@mail.com` → `ann_mail.com.877b4e30`), so it stays readable and two texts never become one. A principal from outside (`Principal.parse`, `fromJson`, a participant's, a session's) is checked (`ArgumentError`); a host makes its ids from outside with `levelOf` (Tephra: `Who.viewer`, `Who.remote`).

A principal has **parts**: `child(name)` adds a level (`studio` → `studio/sound`, `module/orders` → `module/orders/sync`), so what each part of a module does is told as that part's in causes, call records and `explain`, for audit. `isWithin(other)` tells a part of `other` at any depth, `parent` the whole it is part of (one level up). A part has its whole's rights unless something names the part (§6.2). An id joined to a principal (a remote call's, a guard's) is `<principal>#<id>`, never another level.

A **cause** is why something happens:

```
Cause { by: Principal, parent: message id?, correlation: message id? }
```

- Every message carries a cause.
- Causes are passed explicitly, never through zones (the only zone mark is a query's, §6.6, and it carries no cause). A handler gets its call and takes `call.causeFor(by)` for what it does: nested calls, writes, facts. Its `parent` is the call. A write or call without a cause starts a new chain on behalf of whoever acts.
- An owner that writes without the call's cause still works, but loses the trail: the journal cannot tell why.
- **A conversation is everything that followed from one message**, however far: a message come in, the call it led to, the timer that call set and what it did minutes after. `correlation` is the id of the message that started it, the same on every message of it; a message that starts one has none, its conversation is its own id (`cause.conversationOf(id)`). `child` keeps it; a cause made by hand that names only its parent (`Cause(by, parent: fact.id)`) is put in that parent's conversation by the registry, which remembers the conversation of each call and fact it saw (as many as `dedupLimit`). `parent` says what caused a message, `correlation` what it is part of: a trace covers one request, a conversation the whole of it, across processes and over days.
- `registry.conversation(id)` answers what the registry still remembers of one: its calls, changes and facts, in order. Spans carry it (`conversation`, §9.2), so a backend finds one by it; `why` tells it (§16).

## 5. Messages, sequence and epoch

- Every message has an **id**: 128 random bits as 32 hex digits, unless the sender gives its own. An id is unique, not secret: nothing is granted by knowing one (over remote, ids are per principal, §14), so the bits come from a plain random source, cheaper than a secure one and there on every platform.
- A registry has an **epoch**: an id made when it starts. Sequence numbers are only comparable within one epoch; a client that sees a new epoch starts over from a snapshot.
- Every committed state change and fact gets the next **sequence number** (`seq`) of the epoch. Within a registry, seq is a total order consistent with causality.

## 6. Vocabulary

### 6.1 States

```
StateDescriptor { name, type, key: entity kind?, readers: { selector: allow | deny }?, meta }
```

- A state has exactly one writer: whoever defined it holds the only write handle.
- A state that goes (its handle disposed, its participant gone) takes its values with it as removals, committed in one tick whoever follows them is told: inside a batch they commit with it, and what the batch wrote of the state goes uncommitted. Its name is free at once.
- `dispose()` ends what follows the registry: its watches, status streams and feeds are done.
- `readers` say who may read its values over remote and to agents, with the selectors of `callers` (§6.2); none means everyone. Its descriptor stays in the catalog for all; `describeFor` lists the states and facts the principal may not read (`unreadable`), `mayRead(principal, name)` tells one. Code in the registry's own process reads every state: readers bound remote participants, not the host.
- A keyed state holds one value per key; an unkeyed state holds one value.
- Reading gives the last committed value, or nothing when there is none.
- Removing a key or the whole state is a change like any other.

### 6.2 Commands

```
CommandDescriptor {
  name, params: object type, returns: type?, owner,
  callers: { selector: allow | warn | deny },
  deadline: duration, meta
}
```

- Exactly one handler per command; defining a command registers its handler.
- **A command asks; its owner writes.** A state is written by its owner only (§6.1), never by the registry on someone's behalf. A command says nothing of which states its handler writes: that is the owner's to decide and to change, and what it did is told after, by the causes of the writes (§5, `explain`).
- `callers` are **selectors**: `*` (anyone), or a path (§4): a kind (`user`), a principal (`plugin/hydra`), a part (`module/orders/sync`), any level between (`viewer/twitch`, every viewer of one platform). A selector names everything under it. For a principal the nearest said wins: its own path, then each level up to its kind, then `*` (for `viewer/twitch/123`: `viewer/twitch/123`, `viewer/twitch`, `viewer`, `*`); a principal matched by none is denied. A nearer rule overrides a wider one either way (`module/orders: allow`, `module/orders/sync: deny`). A selector that is not a path (`plugin:hydra`) is refused where it is said (`ArgumentError`), rather than matching nobody. `warn` allows the call; it exists for editors, which tell the author that, for example, any viewer can now do this.
- `deadline` bounds the handler; the default is 30 s, and none (zero or less) is refused.
- The owner may give an **availability** check: synchronous, reads committed state, returns nothing or a reason. `whyUnavailable(command)` asks it without calling, so a client can show a button greyed with the reason.
- A word that only answers is not a command but a query (§6.6).

### 6.3 Facts

```
FactDescriptor { name, type, open: bool, readers: { selector: allow | deny }?, meta }
```

- `readers` say who may hear it over remote and to agents, as a state's (§6.1).
- The definer holds an emit handle. When `open`, the host may hand more emit handles for the same fact to other producers (the chat of several platforms).
- A fact has an id. A fact whose id was already seen within the dedup window is dropped: producers may retry.
- One id is one message, of whatever kind: a cause's `parent` and `recentFact(id)` find the message by it. A random id (§5) is that by itself. A sender that gives its own ids keeps them apart; the registry drops a repeat only among facts (and among calls, §9), never a call and a fact of one id. One event said as two facts (two versions of a word) takes an id per fact, each stable across retries (`<id>` and `<id>:v1`), and one cause.

### 6.4 Catalog

Descriptors come and go at runtime (a plugin starts or stops).

**Old names.** Words are a public API: plugins, agents and the calls a host stores name them. A word renamed keeps its old name as an **alias**: `alias(old, now)` makes `old` stand for the word in calls, reads, watches, facts, `explain` and subscriptions over remote; `canonical(name)` tells what a name stands for. An alias is not a word: it cannot be defined, nor be one already. `describe` lists the aliases (`aliases: {old: now}`); a mirror reads through them; the agent's `describe` says them as `renamed`. Adding or dropping one is a catalog change (`AliasChanged`).

 The catalog is the current set of descriptors and entity kinds; every addition, removal and `entitiesChanged` is a catalog change with its own stream. Removing a command fails the calls waiting in its before stage with `unknownCommand`; a running handler finishes.

### 6.5 Word status

Words come and go while the app runs (a plugin starts, a remote owner leaves, a flag turns a feature off), so a part that uses a word asks whether it can, not once at start but whenever it matters. `statusOf(name, by:)` answers for one principal:

| Status | When |
|---|---|
| `WordMissing` | no word of that name in the catalog |
| `WordNotPermitted` | a state or a fact whose `readers` do not let it read; a command whose `callers` deny it (`warn` allows) |
| `WordUnavailable(why)` | a command whose availability check says why it cannot run now |
| `WordReady` | otherwise |

An old name has the status of its word. `statusChanges(name, by:)` gives the status now, then each change: on a catalog change, after every tick, since the availability check reads committed state, and on `availabilityChanged(command)`, for a check that changes with no tick (a remote owner's, §22.4); a tick that leaves it as it was tells nothing. Nothing about an absent word fails: a read of it is null and a listener of it hears nothing until it comes, so parts start in any order; its status is how a part tells absent from silent. `unavailable` lists the commands that cannot run now, with why.

### 6.6 Queries

```
QueryDescriptor {
  name, params: object type, returns: type, owner,
  askers: { selector: allow | warn | deny },
  deadline: duration, meta
}
```

A **query** only answers: a search, a page, a snapshot by params that no state holds. It is a word of its own kind (`is: query` in `describe`), beside states, commands and facts, so a reader of the catalog, an agent or a generator never mistakes it for a command. Many consumers of one value that changes is a state; one asker's answer by its own params is a query; anything that changes the world is a command.

- It is called through the stages of a command (§9), less what a question has no use for: no dedup (an id is not held to a first answer, asking again asks again) and no call record, so its answers take no memory.
- `askers` are who may ask, selectors as `callers` (§6.2); availability and guards apply as to a command. Through a participant they default as readers do: its `access.read`, else everyone (§22.2). `returns` is required: a query answers.
- In Dart it is `IQueryWord<P, R>` (§18): defined with `query(word).define(handler, askers:)`, asked with `.ask(params)`; its handler gets a `QueryAsk` (params, who asks, `askingFor(by)` for a query it asks in turn), not a call to write with.
- **It is held to changing nothing.** The registry runs its handler marked as the query's (`asQuery`, a Dart zone: it goes with the handler's code through awaits and the timers it starts). A write, a removal, a fact or a command call made there is refused where it is tried (`QueryEffect`: `orders.page is a query, it changes nothing: it tried to write orders.last`), so the query ends `failed` and nothing changed; it may ask other queries. The mark hides nothing: a closure still sees what it captured, and what it tries through parlance is refused. What goes past parlance (a request over the network, a file, a device's port) the registry cannot see: that a query changes nothing there is the owner's promise. A remote participant runs its queries' handlers the same way and refuses what they ask.

| | command | query |
| --- | --- | --- |
| does | changes something: writes, says, calls | only answers |
| a repeated id (§9.1) | answers the first result, runs once | runs again |
| call record | kept | none |
| who may, through a participant (§22.2) | `callers`, else `access.call`, else refused | `askers`, else `access.read`, else everyone |
| `describe`, MCP | `is: command`, an action | `is: query`, safe to ask |
| what its handler tries to change | done | refused (`QueryEffect`), the query fails |
| in Dart (§18) | `ICommandWord`, `command(word).call` | `IQueryWord`, `query(word).ask` |

### 6.7 What a part says of itself

Removed: what a part owns, the registry knows from what it defined; what it needs of others, it asks by the word's status (§6.5), when it needs it.

### 6.8 Who uses a word

Words are a public API (§17), and inside one build the compiler knows who uses each. What it does not see are the users outside the build: remote participants, plugins, agents, a phone. The registry counts them, so a team knows when an old word (an old version, an old name) is no longer used and can go.

- **What counts.** A call or an ask, by anyone (refused too: the caller depends on the word). A session's subscription (its mirror's listeners), while it lasts. A read from outside the build: a session's `recent` or `why`, an agent's read, `why` or recent facts through its tools. What the app's own modules read and watch in this process is not counted: the compiler knows it, and it would cost every read.
- **As it was named.** A use of an old name (§6.4) is counted under that name, so `usesOf('audio.silence')` says who has not moved to the new one.
- **Bounded.** Only a name there is a word of (or an old name of one) is counted, so a peer's made-up names keep nothing; for one word at most `usersPerWord` (64) principals are told apart, the rest counted under their kind alone (`viewer`).
- `usesOf(name)` and `usage` answer, per principal, `WordUse { by, calls, reads, listening (now), last }`. A use is never forgotten while the registry lives; outliving it (a count over weeks, from every host) is the host's to store. A subscription to a word not there yet counts from when the word comes.

## 7. Ticks

A **tick** is the unit of change: every state write and fact made in it is committed together. The registry keeps its states, facts, commands and ticks on the core (§21): its hub commits, and its ticks are the hub's, with names, ids, causes and the time.

- A write or emit outside a batch is a tick of its own. `batch(fn)` runs `fn` synchronously and commits everything it wrote as one tick. Batches nest; the outermost one commits. A batch is whole or nothing: when `fn` throws, nothing it wrote or said is committed (an outer batch that catches it keeps what it wrote itself), and the error goes on.
- Inside a batch, reads see the batch's own writes (read your writes); everyone else sees nothing until the commit.
- On commit, writes that leave a value unchanged are dropped; each remaining change and each fact gets its seq; the tick is delivered as one message: `Tick { epoch, from, to, changes, facts }`.
- Delivery is asynchronous and in seq order. A subscriber that throws does not stop the others; the error goes to the host's error sink.
- Observers (a host's rules, the remote feed) evaluate per tick, never in the middle of one: two states the owner changed together are never seen half-changed.

## 8. Layers

Removed: a state is written by its owner only (§6.2). "While this holds, keep that" is the host's to do with its own rules, or the owner's.

## 9. Calls

```
call(name, params, by: Principal, id?, override = false) → CallResult
```

A call goes through these stages, in order; the first refusal ends it:

1. **Dedup.** (Not for a query, §6.6.) A call whose id was seen within the dedup window returns the result of the first one; it is not run again. Clients retry with the same id. An id stands for one call: the same id with another command, params or principal is refused (`idConflict`), never answered another call's result. Only an id the caller gave is remembered (one the registry made is nobody's to retry with), and at most `dedupLimit` of them (10 000, the oldest going first; so too the ids of facts): a retry of one forgotten runs again.
2. **Lookup.** Unknown command → `unknownCommand`.
3. **Params.** Checked and filled with defaults → `invalidParams`.
4. **Policy.** `callers` for the principal → `notPermitted`.
5. **Availability.** The owner's check → `unavailable`.
6. **Guards.** Every guard (§10) is asked; the first denial → `denied` with the guard's id and reason. A denial marked overridable lets the call through when `override` is set and the principal's kind is one the host allows to override; the call record says it was overridden.
7. **Handler.** Gets the call (id, params, cause), bounded by the deadline → `timedOut`; a throw → `failed`; a result that does not pass `returns` → `failed`. **`timedOut` is not an end**: it means no answer came within the deadline. The handler is told (`call.expired`) and may stop; if it goes on, what it does stands, its end is published as a second call record marked `late`, and a retry with the call's id answers that end.

`CallResult<R>` is `done(value)` (the only end that carries an answer, of type `R` for a typed call, §18) or `refused(code, reason, guard?)`, `failed(error)`, `timedOut`, or `lost(id, reason)`: the answer did not come back over remote (§14), so whether it ran is unknown; a retry with the id runs it at most once. An end a peer of a newer protocol tells that this side does not know (a refusal code, a shape) is `failed`, saying what came: not done, and nothing to retry. A timed-out call's late end takes the place of its timeout among the call records kept. Every finished call is published as a **call record** (request, cause, stages passed, result, override, timings) on the calls stream, for journals. A call whose handler begins is told first on `callStarts` (`CallStarted`: id, command, params, cause, when it came), and `running` lists the calls whose handlers run now, one that timed out too until its handler ends: what a monitor needs to see what is in flight or stuck. Both only tell: nothing in them can change a call. A refused call never begins; a query is not told, as it is not recorded (§6.6).

### 9.2 Logs and telemetry

The registry logs to a `LogScope` of rpc_dart's logger (`package:rpc_dart/logger.dart`, `Registry(log:)`, `LogScope.noop` unless given), the only part of rpc_dart it uses, held as rpc_dart holds it. Without one nothing is logged and nothing of it is made: every line is built behind its level's guard (`isDebug`, `isEnabled(level)`), false on `noop`, and the registry keeps no span and no trace of a message. Its parts log as children of that scope, so their levels are set apart: `calls`, `ticks`, `catalog`.

- **Spans are telemetry, not log lines.** Every call its handler serves is a span, whatever the level (the logger lets spans past its level filter). Telemetry is turned off by `LogController(spansEnabled: false)`, or is off while the controller has no sink: a span the log keeps none of has no id, and the registry gives it no data and keeps nothing of it; what a handler logs in it is told as plain events. It opens with the command's name and carries the call's id (`call`), what it follows from (`parent`), the conversation it is part of (`conversation`, §4: an attribute a backend searches by, which a trace id is not) and who calls; its params only when `calls` takes debug. It ends when the handler ends: `ok`, or `error` with what failed. A call that timed out gets a `timed out` event and stays open until its handler ends, then is marked `late`. A query is a span too.
- **Traces follow causes.** A call whose cause's parent is a call still running is a child span of that call's; else its span starts a trace of its own, with a W3C trace id. Across a connection the call to a remote owner carries its span as a W3C `traceparent` (`WireServe.traceparent`), and the participant serves it in a child span of that one, in the host's trace (`startSpan(parent:)`). With the OTel bridge given `LogSpanIds`, the backend sees one trace across both. Inside an RPC handler a call's span is a child of the RPC's when the log's controller has `ambientParent: otelTraceparent`.
- **What answers a message links it.** A call whose cause's parent is over by the time it is served (a fact, a call that ended) starts a trace of its own and links the span that said it (`startSpan(links:)`, an OTel span link): the registry keeps the trace of each fact said in a call's span, or following a message that had one, and of each call that ended, as many as ticks are retained. A viewer's chat line, the plugin's command that answers it: two traces, linked.
- **Events by level, made only when taken.** A span keeps every event it is given, whatever the level, so an event is made only behind the level's guard: at debug, each write and fact made with the call's cause is an event of its span (`wrote`, `removed`, `said`). The handler gets the span, `call.span` (`ask.span`); without a log it is the one span of `LogScope.noop`, ended, taking nothing. It logs `call.span.event(...)`, an event whose message or data costs something behind `span.isEnabled(level)`; the span drops an event its level does not take. Passed explicitly, as causes are, never through zones.
- **Messages are constant; what varies is in `data`** (`refused` with `command`, `code`, `reason`, `guard`, `by`, `id`), so a line is searched and counted by its fields. Each is made behind `isEnabled(level)`, so a level the logger does not take costs neither a string nor a map. Refusals are `info` (a refusal is an answer, not an error); an asked guard that could not answer is a `warning`; ticks are `debug` (`seq`, the states written, the facts said), the catalog `info` (`defined`, `removed`, `alias changed`; `kind changed` at debug), and every error that goes to `onError` an `error`.

## 10. Guards

```
addGuard(id, check, overridable = true) → handle
```

- `check` is synchronous, reads committed state only, makes no calls, and returns nothing or a denial reason.
- An id is one guard's in the registry; a participant's guard is registered as `<principal>#<id>` (§22), so participants never take one another's ids.
- `addAskedGuard(id, ask, overridable, timeout)`: a guard another makes across a connection (a remote participant's, §22.4), asked in the same turn as the others and awaited; no answer within `timeout`, or a failure to ask, denies. Since it takes a while, the command's `available` is asked again after: one that cannot run by then is `unavailable`.
- Guards are asked for every call that reached stage 6.
- A guard that throws denies (`denied`, with its id), as one asked across a connection that cannot answer does: the rule it keeps holds. The error goes to the error sink.

## 11. Before hooks

Removed: what should happen before or after a command is its owner's to do, or the host's rules on ticks and facts (§7). Guards (§10) say whether a call may go on.

## 12. The feed

Remote clients and journals read the registry as a feed:

```
feed(since?: (epoch, seq)) → Snapshot? then Tick, Tick, …
```

- Without `since`, or with another epoch, or with a seq older than the retained ticks: first a **snapshot** (every state value, the catalog, the epoch and seq), then live ticks. A snapshot after a gap says `factsLost: true`.
- With a seq still retained: the retained ticks after it, then live ticks, with no gap and no repeat. What each kind of message is promised across a drop: §14.1.
- The registry retains the last ticks by count (default 1000) and the last facts per name (default 100) for `recent(name, n)` (none for an `n` of none or less), the call records as many as ticks; each of these histories also keeps no more than about `retainBytes` (default 4 MB) of values, weighed roughly as their JSON. Whichever bound comes first drops the oldest, but the newest of each history is kept however big, so a big value rewritten often is not held in every version. `explain` says when what it cannot find may be forgotten: `forgotten` (the last change), `trailCut` (earlier calls). `describe` tells the dedup window (`dedupWindowMs`): how long an id answers its first result.

## 17. Versions

`describe` over remote carries the protocol version (now 2: calls answer their seq, `recent` was added); the registry's own `describe` does not. What a host exports in the registry's terms carries a format version; the importer refuses a newer major version and migrates older ones.

## 18. Typed words

The registry keeps names and JSON, as remote participants and agents see it. A host names its words once, with their Dart types, and works through them; nothing else in its code types a name or a param key.

- **Words.** `IStateWord<T>` (name, shape, key kind), `ICommandWord<P, R>` (name, params as a `RecordShape<P>`, answer as a `Shape<R>` or none, then `R` is `void`), `IQueryWord<P, R>` (name, params, answer as a `Shape<R>`, always), `IFactWord<T>` (name, shape). A query is not a command in Dart: it is defined with `query(word).define(handler, askers:)` and asked with `.ask(params)`, never called, and where a command is wanted it does not fit. A host's enum of its words implements them; each value carries its own types (`enum ScenesCommand<P, R> implements ICommandWord<P, R> { show<({String scene}), void>(...) }`).
- **Shapes** say how a JSON value is a Dart one, and give the registry its type: `Plain(BoolType())` is a `Shape<bool>` (the value type's own Dart type: `ValueType<T>`), `EnumShape(values)` a Dart enum kept as its name, `ListShape(item)`, `RecordShape(fields, to:, from:)` an object as a record, its field names written beside the fields and nowhere else. `RecordShape.none` is the params of a command that takes none.
- **More shapes:** `Nullable(shape)` for null or a value (a state whose "none" means something, such as every app), `MapShape(value)` for a map from text, and `UnionShape(key, {tag: RecordShape}, tagOf:, descriptions:)` for one of several objects as a sealed class. `Part(description:)` describes a field.
- **A class that serializes itself** (json_serializable, freezed): `JsonShape(Order.fromJson, (o) => o.toJson(), type:)`. Its `type` (an `ObjectType` of its fields) lets the registry check writes and `describe` tell the shape; without one any object passes. `toJson` must give plain JSON all the way down (`explicitToJson: true`), or the write is refused with that said. A generator may make the `type` from the class's fields.
- **Through the registry** (the package's own; a host does all of it on a participant, §22). `state(word)` defines (`StateWriterOf<T>`), reads, watches; `command(word)` defines with a handler that gets typed params (`CommandCallOf<P>`) and returns `R`, and calls with `P`, answering `CallResult<R>`; `fact(word)` defines (`FactEmitterOf<T>`), streams and lists `Fact<T>`. Refusals, failures, `timedOut` and `lost` are `CallResult<Never>`, so they end a call of any answer type.
- **The word fixes the types.** A call is made on what `command(word)` gives, never by a generic function taking a word and params together: Dart's generics are covariant, so such a function would infer a common supertype of two different records and compile a call with another command's params.
- An answer that does not decode as the word says is `failed`.
- A state's value decodes once per value: reads and watches of the same value share one decoded Dart value, so the lists and maps a shape decodes are unmodifiable.
- A change reaches only the watchers of its state and key: a write costs the same however many watch other states or keys. A watcher is told the value when it starts, then only what was committed after: never a tick older than what it read first.
- `readAll` of a state that may be null (`Nullable`) keeps its null values: null is a value of its own there.
- **As the core sees them.** The typed handles are the core's interfaces (§21.6): `StateOf.reader`, `StateWriterOf` and its `at`, `CommandOf.caller(by:)` (`CallNotDone` for a call not done), `FactEmitterOf`, `FactOf.listener`. Names and keys of entity kinds stay strings.

