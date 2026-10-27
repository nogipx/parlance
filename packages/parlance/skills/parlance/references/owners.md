# owners: what every host that puts words in a registry needs

## 19. Owners

A host's words have owners: one owner writes a state, serves a command, emits a fact (§6). `package:parlance/owners.dart` curates what each owner otherwise writes by hand. It uses the registry's public API only.

- **`Owner`** (abstract base): code that owns words, speaking through the participant it is attached to (§22). It says nothing of who it is or what it may: `main` says that when it makes the participant. `define(IParticipant p)` defines its words through typed words (§18) and keeps each returned handle with `keep(...)`. `keep` gives the handle back with its own type: `_mode = keep(p.state(HouseState.mode).define())`. `sync()` writes its states as its devices or ports have them now. `dispose()` withdraws its words, the last kept first. An owner attaches to one participant, once (`attach(p)`); `participant` before that throws.
- **`trackKind(name, list)`**: registers a kind of entities the owner keeps. Its `sync()` compares the entities with those seen last (ids and labels, in order). When they differ it announces `entitiesChanged`, and it answers the ids that went, so the owner removes their keyed states. It announces nothing while nothing changed.
- **`listen(stream, onData)`**: listens while the owner is attached, for what its work reports on its own (a switch flipped by hand, a message come in) to write or emit; the subscription goes with the owner.
- **`Owners(participant, {name: owner, ...})`**: a module of several owners on one participant, `main`'s: attaches each to the part of its name (`participant.child(name)`, §22.3), so its acts are told as its own, in order, then syncs them. Its `sync()` calls every owner's `sync()` in one batch of the participant, so a change is one tick, seen whole, over a connection too. `dispose()` withdraws the owners, the last first, then the parts it made, with all they did; the participant stays, its maker's to dispose.
- **`changes`**: an owner whose model says when it moved (`Stream<void>`: a controller's listener, a device's callback) gives it here; it is then synced on its own, once for all its stream told in one turn of the event loop, and with the others of its group told in that turn as one tick. Without it, whoever changes the model calls `Owners.sync()`.
- **`failCall(why)`**: a handler whose device or port said no ends the call as `failed` with `why` (a `CallFailure`, told as it is, no exception type before it). A refusal with a code (`notPermitted`, `unavailable`, `denied`...) comes only from the registry's own stages (§9): to refuse before a call runs, give the command `available`.
- **`Handles`**: the set an owner keeps, usable on its own. `keep` after `dispose` withdraws the new handle at once and throws.

### 19.1 Words it uses

- **`words`**: the words it owns, `[...OrdersState.values, ...OrdersCommand.values]`. When it attaches, every one must lie in the participant's namespaces, or `NotPermitted` comes before it defines anything; then the participant declares them with its uses (§6.7), so `describe` tells what each part owns and needs. It may still define words it does not list, within its namespaces (a name known only at run time).

- **`uses`**: an owner says which words of others it uses, `Use.required(word)` or `Use.optional(word)` (any typed word, `IWord`). An optional one it handles being missing, not permitted or unavailable (§6.5); a required one it cannot work without.
- **`Owners.checkUses()`**: once every group of the app is attached (a word of one group may be another's, and the order they attach in does not matter), `main` awaits each group's check. It waits until the participant's view of the catalog is the registry's (`settle`, §22), then takes each owner's required words as its part sees them: missing or not permitted is unmet; a command unavailable now is there. It throws `UnmetUses`, a `StateError` naming every unmet word with the part that needs it (`host:needy needs test.level: missing`), so the app stops at start with a clear message rather than a part failing later.
- It checks at start only. Words come and go while the app runs (a remote owner leaves, a plugin is turned off): then a part reads their status, never the start's answer. It checks names and whether the part may use them, not a word's kind or type.

A host calls `Owners.sync()` when its own model changed and its owners give no `changes`: on a listener of its controller, a device callback, a timer.

### 19.2 Scopes

A group of owners is a scope: `main` attaches it when what it serves begins and disposes it when that ends, and what it held leaves the registry with it.

- **App**: for the life of the process (sign-in itself, sync, settings).
- **A user's session**: from sign-in to sign-out. The group is made on sign-in, its participant with the user's modules' namespaces, and disposed on sign-out: its words, values, kinds, guards and declarations go, so nothing of one user reaches the next, whatever each module remembered to clear. Others see its words `missing` (§6.5) until the next session defines them.
- **A feature**: made when it opens (a route, a deferred import), disposed when it closes; outsiders see its words missing meanwhile, and their own `uses` of it are optional.
- **Not in the registry**: a screen's own state, which no other part reads.

One word lives in one scope: a word two scopes need belongs to a group above both, never to both (namespaces are exclusive, §22). A scope's required `uses` are checked when it is made (`checkUses`, §19.1).
