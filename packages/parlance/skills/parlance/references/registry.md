# parlance contract: registry (§1, §2, §3, §4, §5, §6, §7, §8, §9, §10, §11, §12, §17)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

**What a host holds.** `main` makes the `Registry`, makes its participants (§22) and watches it; it does nothing on anyone's behalf through it. Exported are its making (its bounds, clock, log), `participant(...)`, and what only tells: the catalog and its changes, `describe`, `ticks` and `seq`, `calls`, `callStarts`, `running`, `callRecord`, `explain`, `lastChange`, `conversation`, `usesOf`, `usage`; and what is the host's alone to say: `alias` (§6.4), `registerType` (§2), `dispose`. Everything that acts, the sections below describe as the registry's (defining words with `by:`, calling and writing as any principal, guards, kinds, batches, reads, watches and facts by name, status by principal, the feed), is the package's own (`RawRegistry`, and the typed `registry.state(word)` and the rest, §18): participants, sessions and views are built on it, and a part reaches it only as one of them, so no code but the package's can act as someone it is not, or define a word outside its vocabularies. A test of the package imports it from `src/`.

## 1. Values and names

**Values** are JSON values: `null`, `bool`, `num`, `String`, `List`, `Map<String, Object?>`. Everything a registry sends, and everything it tells by name, is a value, so it crosses a process boundary and is persisted without codecs. A word a typed owner defines in this process is kept as its Dart value, held to the same rule as its JSON (§18); every other is kept as JSON. Either way values are deep-frozen when they enter the registry, and equality is deep: the JSON's.

**Names** are lower-case words split by `.`, each from a letter, its parts joined by `_` or `-`: `^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)*$` (`house.door.left_open`, `kitten-daycare.lights`). The two joiners are different signs: `muted-talk` and `muted_talk` are two names; `.` only ever splits; every other sign is reserved. The same holds for entity kinds and type names. A vocabulary's name is one such word, no `.` (a plugin's id is the vocabulary of its words). The first word is the owner's vocabulary; the registry does not enforce ownership by name, only by handle (participants do, §22.1). A word generated from a vocabulary (§23) is stricter: `<vocabulary>.<name>[.vN]`, its name one word said in its annotation and never `v2` (that reads as a version), so no other `.` appears in it.

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
| `enum` | one of the given strings | `values`, `unknown` (what code reading it takes a value it does not know for, §25.2) |
| `duration` | `int`, milliseconds, ≥ 0 | `max` |
| `ref` | entity id `String` | `kind` |
| `list` | `List` of one type | `item`, `maxItems` |
| `object` | `Map` with named fields; unknown ones refused, an optional one given as null left out (but for a nullable one, where null is its value) | fields: type, `optional`, `default`, `description` |
| `map` | `Map` from any text to one type (files by path) | `value`, `maxEntries` |
| `nullable` | null, or a value of `of`: "none" as a value of its own, apart from an empty list | `of` |
| `oneOf` | one of several objects, told apart by the text in field `key` | `key`, `variants` (objects by tag), `descriptions` |
| `custom` | anything the host's checker accepts | `name` |
| `any` | any value | |
| (another) | a type of a newer parlance, read from the wire as `UnknownType`: told on as it came, a word of it not taken (§14) | its JSON |

- `ref` is valid when the host registered the kind and the kind contains the id at the time of the check.
- `object` rejects unknown fields, fills missing optional fields with their default (or leaves them out when there is none), and rejects missing required fields.
- `custom` types are registered by the host: a name and a checker. The package never interprets them.

## 3. Entity kinds

The host registers entity kinds: a name and a function listing the current entities (`id`, `label`, and `meta`: what else an editor or an agent needs, such as the type of the value it takes). The registry uses them to check `ref` values and to answer `describe`. When the entities of a kind change, the host says so (`entitiesChanged`); the registry passes it on in its catalog changes.

## 4. Principals and causes

A **principal** is who acts: a `kind`, an `id` within it, and the `owner` of it that acts, if one does. Kinds are an open set declared by the host. The package reserves one: `system` (the registry itself).

**A principal is `kind[/id][@owner]`.** Its selector is its kind, its id after `/`, its owner after `@`: `user/local`, `module/visit`, `guest/bob`, `home@house`, `module/visit@visit`. Each is one part, never more: an id is one level, an owner one name, and an owner has no owners; so `/` and `@` only ever separate, and a selector says which is the id and which the owner. An id holds letters, digits, `.`, `-` and `_` only, as gRPC names do; every other sign is reserved (`/`, `@` and `#` have their uses, the rest are kept for later). A kind (from a letter) and an owner's name are ours, as names are: lower-case letters and digits joined by `_` or `-` (`house@door_lock`); an id may come from outside, letters, digits, `.`, `-` and `_`, and keeps its case (`UCabc` and `UCAbc` are two channels). A text from outside becomes an id by `Principal.idOf`, the rule Kubernetes and Helm name things by: one that is a level already stays as it is; else every run of other signs becomes `_` and 64 bits of a SHA-256 of the whole text are added after a `.` (`ann@mail.com` → `ann_mail.com.1278c97d19647cda`), so it stays readable and two texts never become one. A text that ends as such an id does (`.` and 16 hex digits) is made one too, so a name taken as another's id is not given it. A principal from outside (`Principal.parse`, `fromJson`, a participant's, a session's) is checked (`ArgumentError`); a host makes its ids from outside with `idOf`.

A principal has **parts**, its owners: `child(name)` names one (`house` → `house@heating`, `module/orders` → `module/orders@sync`), so what each owner of a module does is told as that owner's in causes, call records and `explain`, for audit; a part's `child` throws (`StateError`). `isWithin(other)` tells whether a selector of `other` names it: `other` itself, its owners, and for a bare kind all of it; `parent` is one up (`module/orders@sync` → `module/orders` → `module`). A part has its whole's rights unless something names the part (§6.2). An id joined to a principal (a remote call's, a guard's) is `<principal>#<id>`.

A **cause** is why something happens:

```
Cause { by: Principal, parent: message id?, conversation: message id?, origin: Origin? }
Origin { word: name, by: Principal }
```

- Every message carries a cause.
- A handler a participant serves runs in a zone that holds its call: what a participant writes, says and calls there with no cause given takes `call.causeFor(who)`, its `parent` the call, after an `await` too and in a timer it starts. A cause given wins. Outside a handler (and on the registry itself, which acts for no one) a write or call without a cause starts a new chain on behalf of whoever acts. A query's mark (§6.6) is a zone too, and carries no cause.
- An owner that writes without the call's cause still works, but loses the trail: the journal cannot tell why.
- **A conversation is everything that followed from one message**, however far: a message come in, the call it led to, the timer that call set and what it did minutes after. `conversation` is the id of the message that started it, the same on every message of it; a message that starts one has none, its conversation is its own id (`cause.conversationOf(id)`). `child` keeps it; a cause made by hand that names only its parent (`Cause(by, parent: fact.id)`) is put in that parent's conversation by the registry, which remembers the conversation of each call and fact it saw (as many as `dedupLimit`). `parent` says what caused a message, `conversation` what it is part of: a trace covers one request, a conversation the whole of it, across processes and over days.
- **`origin` is what the conversation started with**: the word of its first message (the command called, the fact said) and on whose behalf it was; which conversation it is, the cause's `conversation` (its first message's id) says. The same on every message of it, whoever acts on the way (a guest's ring `house.rang`, the guest book's call that answers it, the owner's write in that call: all of origin `house.rang by guest/bob`), so every message that followed from one word is found by it, and one conversation by `conversation`. A message that starts one has none: it is its own (`cause.originOf(word)`). `child` keeps it, and `call.causeFor` makes it of the call it serves; the registry gives it from the parent, as far as it remembers the parent (`dedupLimit`), never takes it from the cause that acts: a cause that follows from nothing is its own origin, whatever it claims. It tells, it grants nothing: rights are `by`'s (§6.2).
- `registry.conversation(id)` answers what the registry still remembers of one: its calls, changes and facts, in order. Spans carry it (`conversation`, and `origin`, `originBy`, §9.2), so a backend finds one by it; `why` tells both (§16).

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
- `dispose()` ends what holds the registry first, the last made first: its participants (their owners and parts with them) and the sessions it serves, so nothing is closed by hand before it; then what follows it: its watches, status streams and feeds are done.
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
- `callers` are **selectors**: `*` (anyone), or a principal's (§4): a kind (`user`), a principal (`module/visit`), a part (`module/orders@sync`). A selector names itself and its parts, a kind all of it. For a principal the nearest said wins: its own, then its whole, then its kind, then `*` (for `module/visit@visit`: `module/visit@visit`, `module/visit`, `module`, `*`); a principal matched by none is denied. A nearer rule overrides a wider one either way (`module/orders: allow`, `module/orders@sync: deny`). A selector that is not one (`module:visit`, `guest/bob/2`) is refused where it is said (`ArgumentError`), rather than matching nobody. `warn` allows the call; it exists for editors, which tell the author that, for example, any guest can now do this.
- `deadline` bounds the handler; the default is 30 s, and none (zero or less) is refused.
- The owner may give an **availability** check: synchronous, reads committed state, returns nothing or a reason. `whyUnavailable(command)` asks it without calling, so a client can show a button greyed with the reason.
- A word that only answers is not a command but a query (§6.6).

### 6.3 Facts

```
FactDescriptor { name, type, open: bool, readers: { selector: allow | deny }?, meta }
```

- `readers` say who may hear it over remote and to agents, as a state's (§6.1).
- The definer holds the emit handle, and only it says the fact: a fact has one owner, as every word (a part that needs to say what another owns asks it by a command).
- A fact has an id. A fact whose id was already seen within the dedup window is dropped: its owner may retry.
- One id is one message, of whatever kind: a cause's `parent` and `recentFact(id)` find the message by it. A random id (§5) is that by itself. A sender that gives its own ids keeps them apart; the registry drops a repeat only among facts (and among calls, §9), never a call and a fact of one id. One event said as two facts (two versions of a word) takes an id per fact, each stable across retries (`<id>` and `<id>:v1`), and one cause.

### 6.4 Catalog

Descriptors come and go at runtime (a plugin starts or stops).

**Old names.** Words are a public API: plugins, agents and the calls a host stores name them. A word renamed keeps its old name as an **alias**: `alias(old, now)` makes `old` stand for the word in calls, reads, watches, facts, `explain` and subscriptions over remote; `canonical(name)` tells what a name stands for. An alias is not a word: it cannot be defined, nor be one already. `describe` lists the aliases (`aliases: {old: now}`); a mirror reads through them; the agent's `describe` says them as `renamed`. Adding or dropping one is a catalog change (`AliasChanged`). A rename while someone follows the old name goes on reaching them: a watch of it follows the word it stands for now and is told its value as the alias comes, a listener hears the word's facts, and a session's subscription by it carries the word, its values sent as the alias comes; nothing of theirs subscribes again.

 The catalog is the current set of descriptors and entity kinds; every addition, removal and `entitiesChanged` is a catalog change with its own stream. Removing a command fails the calls waiting in its before stage with `unknownCommand`; a running handler finishes.

### 6.5 Word status

Words come and go while the app runs (a plugin starts, a remote owner leaves, a flag turns a feature off), so a part that uses a word asks whether it can, not once at start but whenever it matters. `statusOf(name, by:)` answers for one principal:

| Status | When |
|---|---|
| `WordMissing` | no word of that name in the catalog |
| `WordNotPermitted` | a state or a fact whose `readers` do not let it read; a command whose `callers` deny it (`warn` allows) |
| `WordUnavailable(why)` | a command whose availability check says why it cannot run now |
| `WordMismatch(breaks)` | asked through a typed word: the word is there, but its kind or types break a promise of the one the code was built against (§23.3) |
| `WordReady` | otherwise |

**Typed status: what the code was built against.** A typed handle's `status` and a client's (`wordStatus(view, word)`, `wordStatusChanges`) hold the word met to the word the code holds, by the rule of §25.1, judged as the data goes: what code reads it must read as the word gives it now, what it gives the word must take. A field added to what it reads, a param it may leave out, a bound narrowed on what it reads keep every promise; what does not is `WordMismatch`, its `breaks` every `WordBreak` at once (`path`, `kind`, `was`, `now`, `certain`), each read `path: was …, is …` (`type.max: was 100, is 150`). Each pair of a word and a definition is judged once. So a part built against one version of a module and meeting another (a guest updated over the air, a host behind it) sees what does not match before it calls or reads, here and across a connection (the view holds the word as its catalog told it: `descriptor(word)`). A status by name has no type to hold the word to, and never says it. `wordMismatches(view, words)` names every one of [words] that does not match, with where: what a part checks as it starts, in development (`assert(client.mismatches.isEmpty)`). The host learns the same of every part, as each is made (§6.9). Across a connection a participant tells it itself, with nothing written for it: each word its clients were built against is watched, and one there otherwise is its error, `mismatch` (`{op: built, word}`, every break in the message), and with no log, in development, a line of the developer log; whatever the host speaks.

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
- `askers` are who may ask, selectors as `callers` (§6.2); availability and guards apply as to a command. Through a participant they default as readers do: its `access.readers`, else everyone (§22.2). `returns` is required: a query answers.
- In Dart it is `IQueryWord<P, R>` (§18): defined with `query(word).define(handler, askers:)`, asked with `.ask(params)`; its handler gets a `QueryAsk` (params, who asks, `askingFor(by)` for a query it asks in turn), not a call to write with.
- **It is held to changing nothing.** The registry runs its handler marked as the query's (`asQuery`, a Dart zone: it goes with the handler's code through awaits and the timers it starts). A write, a removal, a fact or a command call made there is refused where it is tried (`QueryEffect`: `orders.page is a query, it changes nothing: it tried to write orders.last`), so the query ends `failed` and nothing changed; it may ask other queries. The mark hides nothing: a closure still sees what it captured, and what it tries through parlance is refused. What goes past parlance (a request over the network, a file, a device's port) the registry cannot see: that a query changes nothing there is the owner's promise. A remote participant runs its queries' handlers the same way and refuses what they ask.

| | command | query |
| --- | --- | --- |
| does | changes something: writes, says, calls | only answers |
| a repeated id (§9.1) | answers the first result, runs once | runs again |
| call record | kept | none |
| who may, through a participant (§22.2) | `callers`, else `access.callers`, else refused | `askers`, else `access.readers`, else everyone |
| `describe`, MCP | `is: command`, an action | `is: query`, safe to ask |
| what its handler tries to change | done | refused (`QueryEffect`), the query fails |
| in Dart (§18) | `ICommandWord`, `command(word).call` | `IQueryWord`, `query(word).ask` |

### 6.7 What a part says of itself

Removed: what a part owns, the registry knows from what it defined; what it needs of others, it asks by the word's status (§6.5), when it needs it.

### 6.8 Who uses a word

Words are a public API (§17), and inside one build the compiler knows who uses each. What it does not see are the users outside the build: remote participants, plugins, agents, a phone. The registry counts them, so a team knows when an old word (an old version, an old name) is no longer used and can go.

- **What counts.** A call or an ask, by anyone (refused too: the caller depends on the word). A session's subscription (its mirror's listeners), while it lasts. A read from outside the build: a session's `recent` or `why`, an agent's read, `why` or recent facts through its tools. What the app's own modules read and watch in this process is not counted: the compiler knows it, and it would cost every read.
- **As it was named.** A use of an old name (§6.4) is counted under that name, so `usesOf('house.lamp')` says who has not moved to the new one.
- **Bounded.** Only a name there is a word of (or an old name of one) is counted, so a peer's made-up names keep nothing; for one word at most `usersPerWord` (64) principals are told apart, the rest counted under their kind alone (`guest`).
- `usesOf(name)` and `usage` answer, per principal, `WordUse { by, calls, reads, listening (now), last }`. What was counted of a name is kept while the name is a word or an old name of one, and goes when it is neither (the word removed, the old name dropped): then there is nothing left to remove that a count would warn of, and names a host makes and drops at run time keep nothing. Who listens to the name at that moment stays counted, so a word defined again under it (a plugin reloaded) goes on counting its listeners. Outliving the registry (a count over weeks, from every host) is the host's to store. A subscription to a word not there yet counts from when the word comes.

### 6.9 What a part was built against

How this fits with the other checks of compatibility: §25. A part updated apart from the others (a guest over the air, a plugin, a host behind its guests) meets words of another version than its code holds. Its own typed status tells it (§6.5); this tells the host, all parts at once, with no code of the part's own.

- **Told as the code is made.** A view's `builtAgainst(words, from:)` tells the registry the view's principal was built against those words, each as its schema entry (§23.3), and from which words package and version (`from`, `notes_words 1.2.0`). A generated client tells it as it is made (§23.5), for its whole vocabulary, `from` its `WordSet`: a word the part never uses may be told as a mismatch, the price of knowing at start rather than at first use. Each word is told once; across a connection the host is told by fingerprint first, the schema only when it does not know it (§25.4), and told again on a new session.
- **Judged as words change.** The registry judges each word told against the word defined under its name (or an old name, §6.4), by the rule of §6.5: as it is told, and whenever the word comes, goes or is defined again (an owner attached, synced, a participant joined again). `mismatches` lists every `Mismatch {by, word, breaks, from}` now; `mismatchChanges` tells each found, changed or ended (`breaks` empty: the word keeps its promises again, is gone, or no part built against it is there any more). A word missing is no mismatch; its status says it.
- **Logged.** A mismatch found is a warning in the registry's `catalog` log, saying who, the word and every break; with no log given, in development (asserts on), it goes to the developer log (`dart:developer`, name `parlance`), so it is seen without code of the host's.
- **Diagnostics, and one leniency.** Nothing waits on it and nothing is refused by it: a part that tells nothing works as before. What to do with a mismatch (not to load a guest, to roll it back) is the host's. It is not what a part needs (§6.7): a part still asks a word's status when it needs it. The one thing the registry does with it: a call by a part told otherwise has the params the command no longer takes left out rather than refused (§25.5).
- **Bounded.** At most `Registry.builtPerPrincipal` (1024) words per principal, and `Registry.knownSchemas` (4096) schemas known by fingerprint; what a part told goes with it (its participant disposed, its session ended, a remote participant closed).

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
call(name, params, by: Principal, id?) → CallResult
```

A call goes through these stages, in order; the first refusal ends it:

1. **Dedup.** (Not for a query, §6.6.) A call whose id was seen within the dedup window returns the result of the first one; it is not run again. Clients retry with the same id. An id stands for one call: the same id with another command, params or principal is refused (`idConflict`), never answered another call's result. Only an id the caller gave is remembered (one the registry made is nobody's to retry with), and at most `dedupLimit` of them (10 000, the oldest going first; so too the ids of facts): a retry of one forgotten runs again.
2. **Lookup.** Unknown command → `unknownCommand`.
3. **Params.** Checked and filled with defaults → `invalidParams`.
4. **Policy.** `callers` for the principal → `notPermitted`.
5. **Availability.** The owner's check → `unavailable`.
6. **Guards.** Every guard (§10) is asked; the first denial → `denied` with the guard's id and reason.
7. **Handler.** Gets the call (id, params, cause), bounded by the deadline → `timedOut`; a throw → `failed`; a result that does not pass `returns` → `failed`. **`timedOut` is not an end**: it means no answer came within the deadline. The handler is told (`call.expired`) and may stop; if it goes on, what it does stands, its end is published as a second call record marked `late`, and a retry with the call's id answers that end.

`CallResult<R>` is `done(value)` (the only end that carries an answer, of type `R` for a typed call, §18) or `refused(code, why, guard?)`, `failed(error)`, `timedOut`, or `lost(id, how)`: the answer did not come back over remote (§14), so whether it ran is unknown; a retry with the id runs it at most once. An end a peer of a newer protocol tells that this side does not know (a refusal code, a shape) is `failed`, saying what came: not done, and nothing to retry. A timed-out call's late end takes the place of its timeout among the call records kept. Every finished call is published as a **call record** (request, cause, stages passed, result, timings) on the calls stream, for journals. A call whose handler begins is told first on `callStarts` (`CallStarted`: id, command, params, cause, when it came), and `running` lists the calls whose handlers run now, one that timed out too until its handler ends: what a monitor needs to see what is in flight or stuck. Both only tell: nothing in them can change a call. A refused call never begins; a query is not told, as it is not recorded (§6.6).

### 9.2 Logs and telemetry

The registry logs to a `LogScope` of rpc_dart's logger (`package:rpc_dart/logger.dart`, `Registry(log:)`, `LogScope.noop` unless given), the only part of rpc_dart it uses, held as rpc_dart holds it. Without one nothing is logged and nothing of it is made: every line is built behind its level's guard (`isDebug`, `isEnabled(level)`), false on `noop`, and the registry keeps no span and no trace of a message. Its parts log as children of that scope, so their levels are set apart: `calls`, `ticks`, `catalog`.

- **Spans are telemetry, not log lines.** Every call its handler serves is a span, whatever the level (the logger lets spans past its level filter). Telemetry is turned off by `LogController(spansEnabled: false)`, or is off while the controller has no sink: a span the log keeps none of has no id, and the registry gives it no data and keeps nothing of it; what a handler logs in it is told as plain events. It opens with the command's name and carries the call's id (`call`), what it follows from (`parent`), the conversation it is part of (`conversation`, §4: an attribute a backend searches by, which a trace id is not), the word it started with and on whose behalf (`origin`, `originBy`) and who calls; its params only when `calls` takes debug. It ends when the handler ends: `ok`, or `error` with what failed. A call that timed out gets a `timed out` event and stays open until its handler ends, then is marked `late`. A query is a span too.
- **Traces follow causes.** A call whose cause's parent is a call still running is a child span of that call's; else its span starts a trace of its own, with a W3C trace id. Across a connection the call to a remote owner carries its span as a W3C `traceparent` (`WireServe.traceparent`), and the participant serves it in a child span of that one, in the host's trace (`startSpan(parent:)`). With the OTel bridge given `LogSpanIds`, the backend sees one trace across both. Inside an RPC handler a call's span is a child of the RPC's when the log's controller has `ambientParent: otelTraceparent`.
- **What answers a message links it.** A call whose cause's parent is over by the time it is served (a fact, a call that ended) starts a trace of its own and links the span that said it (`startSpan(links:)`, an OTel span link): the registry keeps the trace of each fact said in a call's span, or following a message that had one, and of each call that ended, as many as ticks are retained. A guest's ring, the module's command that answers it: two traces, linked.
- **Events by level, made only when taken.** A span keeps every event it is given, whatever the level, so an event is made only behind the level's guard: at debug, each write and fact made with the call's cause is an event of its span (`wrote`, `removed`, `said`). The handler gets the span, `call.span` (`ask.span`); without a log it is the one span of `LogScope.noop`, ended, taking nothing. It logs `call.span.event(...)`, an event whose message or data costs something behind `span.isEnabled(level)`; the span drops an event its level does not take. Passed explicitly, as causes are, never through zones.
- **Messages are constant; what varies is in `data`** (`refused` with `command`, `code`, `reason`, `guard`, `by`, `origin`, `originBy`, `id`, `conversation`), so a line is searched and counted by its fields. Each is made behind `isEnabled(level)`, so a level the logger does not take costs neither a string nor a map. Refusals are `info` (a refusal is an answer, not an error); an asked guard that could not answer is a `warning`; ticks are `debug` (`seq`, the states written, the facts said), the catalog `info` (`defined`, `removed`, `alias changed`; `kind changed` at debug), and every error that goes to `onError` an `error`.

### 9.3 The journal

`registry.journal` tells what happened in the system at the level of use, as it happens and in one order: every call as it begins (`JournalStart`, its `CallStarted`) and as it ends (`JournalEnd`, its call record: done, failed, timed out, late, or refused, which never began), every fact said (`JournalFact`), and every state written in a conversation (`JournalWrite`: its cause has a parent, a call or a fact it answers). An owner's own write of how the world is now (a meter, a clock) is no history and is not in it; what is worth remembering an owner says as a fact. A query is not in it (§6.6). Logs and spans tell how the code ran and may be off, filtered or sampled; the journal is the record of what was done, by whom, following what.

- **Kept by the host, not here.** The stream is synchronous: an entry is with its listeners as it happens, so a writer that listens from the start misses none, whatever comes after. The registry keeps nothing of it, and while no one listens makes nothing of it. A host that must not lose a conversation writes it where it lasts (`parlance_journal` writes JSON lines and reads back a conversation, the one a message is in (`of`), the path to a message (`pathTo`), a conversation as a tree to draw (`tree`), all that one word started (`startedWith`), a trace and the links there are); what the registry remembers (`conversation`, `explain`, call records) is bounded and may forget.
- **An entry** has the registry's `epoch`, its place `n` in it (from 1, no gaps for a listener there from the start), its `kind` (`start`, `end`, `fact`, `write`), its message with `id` and `cause`, and its `word`, its `conversation` and its `origin` (§4: `{word, by}`, its own for the first). `toJson` is one flat object: the message's JSON with `epoch`, `n`, `kind`, `conversation`, `origin` and `trace` beside; `JournalEntry.fromJson` reads it back.
- **Linked to telemetry and logs.** With spans kept (§9.2) an entry carries `trace`, the W3C `traceparent` of the span it is in: a call's own; a fact's or a write's, the span of the call it was made in, or of what it follows from. A span carries `call` and `conversation`, and the registry's log lines `id` and `conversation`, so a conversation found in the journal is found in the backend by its id, and a span or a line leads back to its entry.

## 10. Guards

```
addGuard(id, check) → handle
```

- `check` is synchronous, reads committed state only, makes no calls, and returns nothing or a denial reason.
- An id is one guard's in the registry; a participant's guard is registered as `<principal>#<id>` (§22), so participants never take one another's ids.
- `addAskedGuard(id, ask, timeout)`: a guard another makes across a connection (a remote participant's, §22.4), asked in the same turn as the others and awaited; no answer within `timeout`, or a failure to ask, denies. Since it takes a while, the command's `available` is asked again after: one that cannot run by then is `unavailable`.
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
- The registry retains the last ticks by count (default 1000) and the last facts per name (default 100) for `recent(name, n)` (none for an `n` of none or less), the call records as many as ticks; each of these histories also keeps no more than about `retainBytes` (default 4 MB) of values, weighed roughly as their JSON (a Dart value by its shape, as its JSON would weigh). Whichever bound comes first drops the oldest, but the newest of each history is kept however big, so a big value rewritten often is not held in every version. `explain` says when what it cannot find may be forgotten: `forgotten` (the last change), `trailCut` (earlier calls). `describe` tells the dedup window (`dedupWindowMs`): how long an id answers its first result.

## 17. Versions

`describe` over remote carries the protocol version (now 2: calls answer their seq, `recent` was added); the registry's own `describe` does not. What a host exports in the registry's terms carries a format version; the importer refuses a newer major version and migrates older ones.

## 18. Typed words

A host names its words once, with their Dart types, and works through them; nothing else in its code types a name or a param key. Remote participants and agents see names and JSON.

- **Words.** `IStateWord<T>` (name, shape, key kind), `ICommandWord<P, R>` (name, params as a `RecordShape<P>`, answer as a `Shape<R>` or none, then `R` is `void`), `IQueryWord<P, R>` (name, params, answer as a `Shape<R>`, always), `IFactWord<T>` (name, shape). A query is not a command in Dart: it is defined with `query(word).define(handler, askers:)` and asked with `.ask(params)`, never called, and where a command is wanted it does not fit. A host's enum of its words implements them; each value carries its own types (`enum ScenesCommand<P, R> implements ICommandWord<P, R> { setLight<({String room, bool on}), void>(...) }`).
- **Shapes** say how a JSON value is a Dart one, and give the registry its type: `PlainShape(BoolType())` is a `Shape<bool>` (the value type's own Dart type: `ValueType<T>`), `EnumShape(values, unknown:)` a Dart enum kept as its name (a value it does not know read as `unknown`, else an `UnknownValue`, §25.2), `ListShape(item)`, `RecordShape(fields, to:, from:)` an object as a record, its field names written beside the fields and nowhere else. `RecordShape.none` is the params of a command that takes none.
- **More shapes:** `NullableShape(shape)` for null or a value (a state whose "none" means something, such as every app), `MapShape(value)` for a map from text, and `UnionShape(key, {tag: RecordShape}, tagOf:, descriptions:, unknown:)` for one of several objects as a sealed class (`unknown` makes a variant it does not know from its JSON, §25.2). `Part(description:)` describes a field.
- **What a shape does to a Dart value is what its type does to the value's JSON.** `check(value, ctx, was:)` passes and refuses what the type passes and refuses, with the same words at the same path, fills left-out fields with their defaults, and gives the value unmodifiable all the way down: what the registry keeps. `equals` holds where the JSON is equal; `weigh` is about the JSON's weight. `JsonValue(type)` is the shape of a word with no Dart type: JSON as it is. A `RecordShape` may read its fields by place (`get:`, the generator gives it), so a value is checked with no map made of it.
- **Kept as it is.** A word a participant in this process defines through its typed handle (or with a shape: `defineState(d, shape:)`, `defineFact`, `defineCommand(d, h, params:, returns:)`, `defineQuery`) is kept as its Dart value when its shape can keep one (`keptAsIs`; a class that serializes itself cannot, and is kept as JSON): what is written, said, sent and answered is the same Dart value to whoever reads, hears, gets and is answered with the word's shape (`readAs`, `watchAs`, `factsAs`, `callAs` on a view or participant, §20, §22). JSON is made of it only when asked, once a value: a read by name, a tick's `value` or a fact's `payload`, a call's `params` or answer, the feed, the journal, MCP. A word of another process, or one named at run time, is kept as JSON, and so is what goes across a connection. A value that comes as JSON for a typed word (a call by name, from an agent) is checked as JSON first, then made the word's Dart value.
- **What is the same passes as it is.** A write is checked with the value kept before in its place (`was`): a part of the value that is the same part of it, when its check asks nothing of the registry (no entity, no host's type: `checkedAlone`), is kept already and passes unvisited, its weight the one before told what changed; a list or map the shapes made, of such items, passes whole. What asks the registry is asked again, the same or not, as its JSON would be. So a list of a thousand with one item new costs one item.
- **A class that serializes itself** (json_serializable, freezed): `JsonShape(Order.fromJson, (o) => o.toJson(), type:)`. Its `type` (a `RecordType` of its fields) lets the registry check writes and `describe` tell the shape; without one any object passes. `toJson` must give plain JSON all the way down (`explicitToJson: true`), or the write is refused with that said. A generator may make the `type` from the class's fields.
- **Through the registry** (the package's own; a host does all of it on a participant, §22). `state(word)` defines (`StateWriterOf<T>`), reads, watches; `command(word)` defines with a handler that gets typed params (`CommandCallOf<P>`) and returns `R`, and calls with `P`, answering `CallResult<R>`; `fact(word)` defines (`FactEmitterOf<T>`), streams and lists `Fact<T>`. Refusals, failures, `timedOut` and `lost` are `CallResult<Never>`, so they end a call of any answer type.
- **The word fixes the types.** A call is made on what `command(word)` gives, never by a generic function taking a word and params together: Dart's generics are covariant, so such a function would infer a common supertype of two different records and compile a call with another command's params.
- An answer that does not decode as the word says is `failed`.
- A state's value kept as JSON decodes once per value: reads and watches of the same value share one decoded Dart value, so the lists and maps a shape decodes are unmodifiable.
- A change reaches only the watchers of its state and key: a write costs the same however many watch other states or keys. A watcher is told the value when it starts, then only what was committed after: never a tick older than what it read first.
- `readAll` of a state that may be null (`NullableShape`) keeps its null values: null is a value of its own there.
- Names and keys of entity kinds stay strings.

