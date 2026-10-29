# owners: the code that owns a participant's words

## 19. Owners

A host's words have owners: one owner writes a state, serves a command, emits a fact (§6). An owner is code a participant holds (`package:parlance/participant.dart`, §22.3); it curates what each owner otherwise writes by hand, on the registry's public API only.

- **`IOwner`** (`schema.dart`, an interface with no members): what `main` attaches to a participant (`p.attach({'name': owner})`), once; it speaks as the part of its name. It says nothing of who it is or what it may: `main` says that when it makes the participant. An owner extends a base the generator made (§23.4), which implements it and defines its words; one written by hand implements it and says in its constructor `IOwner.made(this, define: (p) {...})`, keeping each handle with `keep(...)` (`_mode = keep(p.state(HouseState.mode).define())`). It has no member of the library's, so a name of its own is its own, in this version and those to come: what it does with the library it does by the extension **`OwnerTools`**, written as its own (`listen(...)`, `caller`); where it has a member of that name, `OwnerTools(this).listen(...)`. It overrides nothing: what it follows, hears and lets go of it says in its constructor.
- **`follow(pull, {on})`**: for an owner whose states come from a model of its own (a device, a port): `pull` sets them from it, when it is attached, whenever `p.sync()` is called, and when `on` tells it the model moved (`Stream<void>`: a controller's listener, a device's callback), once for all told in one turn of the event loop and with the others of its participant told in that turn as one tick. Said once attached, it runs at once. What it sets equal to what is kept changes nothing.
- **`listen(stream, onData)`**: listens once the owner is attached, for what its work reports on its own (a switch flipped by hand, a message come in) to write or say; the subscription goes with the owner. **`hear(facts, onData)`**: hears another's facts so (`HouseClient(p).rangFacts`): what `onData` writes, says and calls follows from the fact heard, as a handler's follows from its call; no cause passed.
- **`trackKind(name, list)`**: registers a kind of entities the owner keeps, once it is attached. Its `sync()` compares the entities with those seen last (ids and labels, in order). When they differ it announces `entitiesChanged`, and it answers the ids that went, so the owner removes their keyed states. It announces nothing while nothing changed.
- **`whenAttached((p) {...})`**: what needs its participant, after its words are defined (a guard, `p.addGuard(...)`; words named at run time; a client of another's words); at once when it is attached. **`participant`**: that part; before it is attached it throws.
- **`guard(word, id, (params, by) => why)`**: a guard (§10) of its own command, by the call's typed params and on whose behalf it comes; null lets it run. Told to the registry once attached, as `<part>#<id>`; an overrider passes it unless `overridable: false`.
- **Availability, unsaid.** A command's `whyNot` that reads what the registry does not keep (a device, a port) is asked again after each `follow` pull and each event it `listen`s to or `hear`s, once in a turn; its status is told where it changed. No owner calls `availabilityChanged`.
- **`now`**: the time by its registry's clock once it is attached (a test's, when it gives one), the world's before.
- **Words named at run time** (a device found, a plugin loaded): `StateWordOf<T>(name, shape)` and `FactWordOf<T>(name, shape)` are words like a vocabulary's, defined in `whenAttached((p) => keep(p.state(StateWordOf(...)).define()))`, in the participant's vocabulary.
- **`keep(handle)`** and **`onDispose(f)`**: what goes when the owner goes, the last kept first: a handle withdrawn, `f` run (a timer cancelled, a device let go).
- **`caller`**: who it answers where it runs: on whose behalf the call its handler serves came, or the fact it hears; null elsewhere. **`apart(act)`**: runs `act` as its own act, not an answer (a timer set in a handler to act later on its own). **`together(writes)`**: writes as one tick outside a handler, as a handler's or a sync's are.
- **A participant holds its owners** (§22.3): `p.attach({'sound': Mixer(...), 'scenes': ScenesOwner(...)})` attaches each to the part of its name (`p.child(name)`), so its acts are told as its own, in order, then writes what they have now as one tick; it may attach more later, never two of one name, nor an owner attached already. Attaching is all or none: when one owner cannot define its words, those attached in the same call are withdrawn and the error goes on. `p.sync()` runs every owner's `follow` in one batch, so a change is one tick, seen whole, over a connection too; an owner whose pull throws writes nothing of it, the others write what they have, and the error goes on after. `p.dispose()` withdraws its owners, the last first, then all it and its parts did, and frees its vocabularies. There is no group apart from the participant: making one and forgetting the other cannot happen.
- **`Owner`** (`participant.dart`, for tests and tools): an owner written by hand with `define(p)`, `sync()`, `changes` and `dispose()` to override. Its members are its subclasses' names, so it is no frozen contract.
- **`failCall(why)`**: a handler whose device or port said no ends the call as `failed` with `why` (a `CallFailure`, told as it is, no exception type before it). A refusal with a code (`notPermitted`, `unavailable`, `denied`...) comes only from the registry's own stages (§9): to refuse before a call runs, give the command `available`.
- **`Handles`**: the set an owner keeps, usable on its own. `keep` after `dispose` withdraws the new handle at once and throws.

### 19.1 Words of others

An owner says nothing of the words of others it needs. It asks a word's status (§6.5) when it needs it, and reads, listens or calls as that status allows: an absent word fails nothing, so parts start in any order.

A host calls `p.sync()` when its own model changed and its owners' `follow` has no `on`: on a listener of its controller, a device callback, a timer.

### 19.2 Scopes

A participant with its owners is a scope: `main` makes it when what it serves begins and disposes it when that ends, and what it held leaves the registry with it.

- **App**: for the life of the process (sign-in itself, sync, settings).
- **A user's session**: from sign-in to sign-out. Its participant is made on sign-in with the user's modules' vocabularies, and disposed on sign-out: its words, values, kinds and guards go, so nothing of one user reaches the next, whatever each module remembered to clear. Others see its words `missing` (§6.5) until the next session defines them.
- **A feature**: made when it opens (a route, a deferred import), disposed when it closes; outsiders see its words missing meanwhile.
- **Not in the registry**: a screen's own state, which no other part reads.

One word lives in one scope: a word two scopes need belongs to a participant above both, never to both (vocabularies are exclusive, §22).
