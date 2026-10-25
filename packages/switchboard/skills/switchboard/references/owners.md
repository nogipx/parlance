# owners: what every host that puts words in a registry needs

## 19. Owners

A host's words have owners: one owner writes a state, serves a command, emits a fact (§6). `package:switchboard/owners.dart` curates what each owner otherwise writes by hand. It uses the registry's public API only.

- **`Owner`** (abstract base): `define(Registry r)` defines its words through typed words (§18) and keeps each returned handle with `keep(...)`. `keep` gives the handle back with its own type: `_mode = keep(r.state(HouseState.mode).define(by: me))`. `sync()` writes its states as its devices or ports have them now. `dispose()` withdraws its words, the last kept first. An owner attaches to one registry, once; `registry` before that throws.
- **`trackKind(name, list)`**: registers a kind of entities the owner keeps. Its `sync()` compares the entities with those seen last (ids and labels, in order). When they differ it announces `entitiesChanged`, and it answers the ids that went, so the owner removes their keyed states. It announces nothing while nothing changed.
- **`listen(stream, onData)`**: listens while the owner is attached, for what its work reports on its own (a switch flipped by hand, a message come in) to write or emit; the subscription goes with the owner.
- **`Owners(registry, [owner, ...])`**: attaches the owners in order, then syncs them. Its `sync()` calls every owner's `sync()` in one batch, so a change is one tick, seen whole. `dispose()` withdraws the owners, the last first.
- **`failCall(why)`**: a handler whose device or port said no ends the call as `failed` with `why` (a `CallFailure`, told as it is, no exception type before it). A refusal with a code (`notPermitted`, `unavailable`, `denied`...) comes only from the registry's own stages (§9): to refuse before a call runs, give the command `available`.
- **`Handles`**: the set an owner keeps, usable on its own. `keep` after `dispose` withdraws the new handle at once and throws.

A host calls `Owners.sync()` when its own model changed: on a listener of its controller, a device callback, a timer.
