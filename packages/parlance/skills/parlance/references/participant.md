# parlance contract: participants (§22)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

## 22. Participants

A **participant** is a part of the app as it speaks: it sees the registry only through an `IParticipant`, as one principal (`who`). `main` makes one per part and hands it over; the part never gets the `Registry`. So the callers and readers of words hold for it in this process as they do over remote: today any code with the registry can name any principal, a participant cannot.

The same interface serves a registry in this process (`LocalParticipant`, §22.1) and one across a connection (§22.4), so a part's code does not change with where it runs.

### 22.1 Making one

`registry.participant(who, namespaces: {...}, rights: ..., access: ...)` (`package:parlance/participant.dart`).

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
- **`availabilityChanged(command)`**: a check of its own command that reads what the registry does not keep answers otherwise now; watchers of its status are told (§6.5).
- **`batch(writes)`**: its writes and facts in one tick (§7).
- **`declare(declaration)`**: what it owns and uses (§6.7), in place of what it said before; a word it owns outside its namespaces is refused (`NotPermitted`). Withdrawn with the handle or with it.
- **`settle()`**: completes when the registry has done all it asked so far and what it sees of the catalog, so `status` too, is as of then. In the host's process at once; across a connection after the host answered and the catalog was asked anew (the feed brings it in its own time). `Owners.checkUses` (§19.1) waits for it.
- **`clock`**: where it reads the time; the registry's in this process.
- **`dispose()`** withdraws everything it defined, registered and added, and frees its namespaces; its words are then missing to everyone (§6.5).

**Access by default** (`WordAccess(read:, call:)`): who may read its states and facts and call its commands when a word does not say. A word's own `readers` or `callers` replace it whole, nothing merges. Without a default and a word's own, a state or a fact is everyone's to read, and a command is refused at once (`ArgumentError`): who may call it is never left to chance. It is applied as the participant defines, so it goes over a connection as part of the descriptor. A word kept from someone is `notPermitted` to them (§6.5), not missing, so a team sees whom to ask; there are no rights per field: what is private to fewer goes in a word of its own.

| Right | Null means |
|---|---|
| `define(who, d)` | every word in its namespaces |
| `produce(who, fact)` | no open fact of another |
| `speakFor(who, by, fact)` | no one but itself |

### 22.3 Parts and owners

A participant has **parts**: `p.child(name)` speaks as `who.child(name)` (§4), in the same namespaces with the same rights and access. What a part defines, writes, says and calls is told as the part's, so causes, call records and `explain` say which part of a module did it. A cause of a whole it is part of, passed to it (`call.causeFor(studio)` in a handler of `studio:sound`), is taken as its own; a sibling's is refused (`NotPermitted`). A part's guards judge only the commands that part defined. One part per name; it goes with its whole, and going it withdraws what it defined and its own parts. Across a connection a part's acts carry `as` (§14) and the host holds them to that part of the session.

An `Owner` (§19) is code that owns words: it defines them in `define(IParticipant p)` and says nothing of who it is or what it may. `main` makes the participant (its principal, namespaces, rights, access) and attaches the owners: one with `owner.attach(p)`, a module of several with `Owners(p, {'sound': SoundOwner(...), ...})`, which attaches each to the part of its name, so every owner's acts are told as its own, and syncs them as one tick. The names are `main`'s, so an owner cannot pass for another. The same owner attaches to a participant in the host's process or across a connection.

### 22.4 Across a connection

`RemoteParticipant` (`package:parlance/remote.dart`) is the same `IParticipant` over a session (§14); its access by default is its own (`join(connection, access:)`). It joins only over an `RpcClientConnection`: `RemoteParticipant.join(connection)` makes its peer endpoint on the connection's transport (`p.endpoint`, for other contracts on the same connection), starts the connection when it is idle, waits until it is online (a connection that gives up first fails the join), and joins again each time it is back. A connection that does not come back once lost (a wasm module's to its host, one in memory) is one whose factory gives its one transport and that does not reconnect (`shouldReconnect: (_) => false`); one that gives up is told to `errors` (`{op: join}`, `lost`). The host makes the session as it makes a local participant: `RegistryResponder(endpoint, registry, principal:, namespaces:, rights:)`; the session is a participant in the host's process, so namespaces are shared with the local ones and its rights are checked there. The participant learns its principal and namespaces from `describe`.

- **What it asks goes in its order, and one turn of its event loop is one tick.** A define, a write, a fact, a kind, a guard, an availability: each returns at once (its handle, `true` for a fact) and is queued; the queue goes as one `apply` the host runs in one batch. A name outside its namespaces, or an act as another, is refused at once (`NotPermitted`); what the host refuses comes after, to `errors` (`ParticipantError`: the op, the session's status, why). `flush()` completes when the host has answered all it asked so far.
- **Its calls come after what it asked.** A call waits for the queue first, so it sees what the participant wrote; it answers once the mirror has reached what the call wrote (§14).
- **What it does in answer follows from the call.** A handler's writes, facts and calls with `call.causeFor(who)` reach the host before the handler's answer, so their parent is the call being served.
- **It reads its own states as it wrote them, and another's as its mirror has them.** The mirror keeps what it watches (`watch`, `changes`), nothing else: a read of another's state it does not watch is null. A watch tells the first value once the mirror has it.
- **Its guards are asked in their turn.** A guard it adds is registered on the host as `<principal>/<id>` for its own commands, and the host asks it across the connection at the guards' stage (§9, §10), before the hooks; no answer within its time (2 s) denies.
- **Its commands' availability is data.** Its checks run in its process; when one answers otherwise (after a tick it hears, after its own writes, or on `availabilityChanged`), it tells the host, which answers `unavailable` with that reason and says so to watchers (§6.5).
- **Its kinds are lists it sends.** `registerKind` sends the entities, `entitiesChanged` sends them again; the host keeps the last.
- **A lost connection is not its end, while the connection comes back.** While away it keeps what it defines and writes; only what it says waits to be sent. When the connection is back, the host's new session gets, in one tick: its kinds, its words, its own states' values as they stand, its guards, its commands' availability; then the facts it said while away, their ids letting the registry drop one it took before the drop. Its mirror resumes after the seq it has (§12). Calls made while away answer `lost` (§14). The host must have closed the old session first: its namespaces are one live participant's (§22.1).
- **It goes with its session**, or by `close()`, which withdraws its words, guards and kinds and closes its endpoint; the connection stays the caller's to dispose.
- A fact's `true` does not say the host took it: a repeat of an id is dropped there.
