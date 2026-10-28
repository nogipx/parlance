# owners: the code that owns a participant's words

## 19. Owners

A host's words have owners: one owner writes a state, serves a command, emits a fact (§6). An owner is code a participant holds (`package:parlance/participant.dart`, §22.3); it curates what each owner otherwise writes by hand, on the registry's public API only.

- **`Owner`** (abstract base): code that owns words, speaking through the participant it is attached to (§22). It says nothing of who it is or what it may: `main` says that when it makes the participant. `define(IParticipant p)` defines its words through typed words (§18) and keeps each returned handle with `keep(...)`. `keep` gives the handle back with its own type: `_mode = keep(p.state(HouseState.mode).define())`. `sync()` writes its states as its devices or ports have them now. `dispose()` withdraws its words, the last kept first, and the owner leaves its participant: it is synced no more. `main` attaches it to a participant, once (`p.attach({'name': owner})`), and it speaks as the part of its name; `participant` (that part) before that throws.
- **`trackKind(name, list)`**: registers a kind of entities the owner keeps. Its `sync()` compares the entities with those seen last (ids and labels, in order). When they differ it announces `entitiesChanged`, and it answers the ids that went, so the owner removes their keyed states. It announces nothing while nothing changed.
- **`listen(stream, onData)`**: listens while the owner is attached, for what its work reports on its own (a switch flipped by hand, a message come in) to write or emit; the subscription goes with the owner.
- **A participant holds its owners** (§22.3): `p.attach({'sound': Mixer(...), 'scenes': ScenesOwner(...)})` attaches each to the part of its name (`p.child(name)`), so its acts are told as its own, in order, then writes what they have now as one tick; it may attach more later, never two of one name, nor an owner attached already. Attaching is all or none: when one owner cannot define its words, those attached in the same call are withdrawn and the error goes on. `p.sync()` calls every owner's `sync()` in one batch, so a change is one tick, seen whole, over a connection too; an owner whose `sync()` throws writes nothing of it, the others write what they have, and the error goes on after. `p.dispose()` withdraws its owners, the last first, then all it and its parts did, and frees its vocabularies. There is no group apart from the participant: making one and forgetting the other cannot happen.
- **`changes`**: an owner whose model says when it moved (`Stream<void>`: a controller's listener, a device's callback) gives it here; it is then synced on its own, once for all its stream told in one turn of the event loop, and with the others of its participant told in that turn as one tick. Without it, whoever changes the model calls `p.sync()`.
- **`failCall(why)`**: a handler whose device or port said no ends the call as `failed` with `why` (a `CallFailure`, told as it is, no exception type before it). A refusal with a code (`notPermitted`, `unavailable`, `denied`...) comes only from the registry's own stages (§9): to refuse before a call runs, give the command `available`.
- **`Handles`**: the set an owner keeps, usable on its own. `keep` after `dispose` withdraws the new handle at once and throws.

### 19.1 Words of others

An owner says nothing of the words of others it needs. It asks a word's status (§6.5) when it needs it, and reads, listens or calls as that status allows: an absent word fails nothing, so parts start in any order.

A host calls `p.sync()` when its own model changed and its owners give no `changes`: on a listener of its controller, a device callback, a timer.

### 19.2 Scopes

A participant with its owners is a scope: `main` makes it when what it serves begins and disposes it when that ends, and what it held leaves the registry with it.

- **App**: for the life of the process (sign-in itself, sync, settings).
- **A user's session**: from sign-in to sign-out. Its participant is made on sign-in with the user's modules' vocabularies, and disposed on sign-out: its words, values, kinds and guards go, so nothing of one user reaches the next, whatever each module remembered to clear. Others see its words `missing` (§6.5) until the next session defines them.
- **A feature**: made when it opens (a route, a deferred import), disposed when it closes; outsiders see its words missing meanwhile.
- **Not in the registry**: a screen's own state, which no other part reads.

One word lives in one scope: a word two scopes need belongs to a participant above both, never to both (vocabularies are exclusive, §22).
