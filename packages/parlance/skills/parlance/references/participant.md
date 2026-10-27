# parlance contract: participants (§22)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

## 22. Participants

A **participant** is a part of the app as it speaks: it sees the registry only through an `IParticipant`, as one principal (`who`). `main` makes one per part and hands it over; the part never gets the `Registry`. So the callers and readers of words hold for it in this process as they do over remote: today any code with the registry can name any principal, a participant cannot.

The same interface serves a registry in this process (`LocalParticipant`, §22.1) and one across a connection (§22.4), so a part's code does not change with where it runs.

### 22.1 Making one

`registry.participant(who, namespaces: {...}, rights: ...)` (`package:parlance/participant.dart`).

- **Namespaces** are the first words of the names it may define: `orders` for `orders.cancel` and `orders.list.page`; a name equal to a namespace is in it. Without namespaces it defines nothing.
- A namespace is **one live participant's**: one another participant has, or one inside or around it (`orders` and `orders.archive`), is refused at once (`StateError`). It is free again when that participant goes.
- Words the host defines on the registry itself (the links engine, sessions of §14) are not participants' and take no namespace.

### 22.2 What it may do

- **Read, watch, hear, call, ask a word's status** (§6.5) as `who`, through `IRegistryView` (§20) and `watch(state, key:)`: a state `who` may not read is null and watches as null; a fact it may not hear never comes. Its calls are refused as anyone's are (§9).
- **Define words in its namespaces**: `defineState`, `defineCommand`, `defineFact`, or typed, `p.state(word).define()`, `p.command(word).define(handler, callers: ...)`, `p.fact(word).define()`; no `by`, it is `who`. A name outside its namespaces is refused (`StateError`), and so is a command that `sets` a state not in them. `rights.define(who, descriptor)` may refuse more (callers that name outsiders, a kind of word).
- **Write and say as itself.** A write, a call or a fact takes no cause, or one whose `by` is `who`: its own act, or what follows from a call it serves (`call.causeFor(who)`). Another principal's cause is refused, but for a fact `rights.speakFor(who, by, fact)` allows: the fact's cause is then theirs, and so are the rights of what follows (a platform says a chat line for its viewer).
- **Say an open fact of another** (`producer(fact)`) only when `rights.produce(who, fact)` allows.
- **Guards on its own commands** (`addGuard`): a guard it adds judges only calls of commands it defined, never another's.
- **Entity kinds** (`registerKind`, §3) it keeps, and `entitiesChanged` of those only.
- **`batch(writes)`**: its writes and facts in one tick (§7).
- **`clock`**: where it reads the time; the registry's in this process.
- **`dispose()`** withdraws everything it defined, registered and added, and frees its namespaces; its words are then missing to everyone (§6.5).

| Right | Null means |
|---|---|
| `define(who, d)` | every word in its namespaces |
| `produce(who, fact)` | no open fact of another |
| `speakFor(who, by, fact)` | no one but itself |

### 22.3 Owners

An `Owner` (§19) is a participant's code: it says `who`, `namespaces` and `rights`, and defines its words in `define(IParticipant p)`. `Owners(registry, owners)` makes each its participant and attaches it; `owner.attach(p)` attaches it to one made elsewhere, of the same `who`.

### 22.4 Across a connection

A remote participant is the same interface over a session (§14), with the host giving it its principal, namespaces and rights. To be specified with it: what it defines returns its handle at once and what it asks goes in order; a batch is one tick on the host; a guard of its own refuses from its handler as `denied`; it registers its kinds by sending their entities. Until then a remote part uses `ParlanceClient`, `RemoteOwner` and `MirrorView` (§14, §20).
