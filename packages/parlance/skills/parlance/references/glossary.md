# parlance glossary

Every term the package uses, what it means, and where its contract is (§n, as in the other references and `SPEC §n` in the code). The examples are a small studio's: `studio.program`, `audio.muted`, `studio.show`.

## Values, names, types

- **Value** (§1): a JSON value (`null`, `bool`, `num`, `String`, `List`, `Map<String, Object?>`). Everything a registry holds or sends is one, deep-frozen when it enters, compared deeply.
- **Name** (§1): lower-case words split by `.`, joined within by `_` or `-`, `audio.gain.set`, `audio.voice.muted_talk`. The first word is the owner's namespace by convention; ownership is by handle, not by name.
- **Key** (§1): the entity id a keyed state's value belongs to (`mic` in `audio.muted[mic]`).
- **Type** (§2): checks a value and fills defaults; a value itself, so `describe` can send it. `bool`, `int`, `num`, `text`, `enum`, `duration`, `ref`, `list`, `object`, `map`, `nullable`, `oneOf`, `custom`, `any`.
- **`ref`** (§2): a value naming an entity of a kind; valid while the kind lists it.
- **Custom type** (§2): a host's own checker under a name; the package never reads it.
- **Entity kind**, **entity** (§3): what keys and refs point at. The host registers a kind with a function listing its entities, each an `EntityRef(id, label, meta)`; it says `entitiesChanged` when the list changes.
- **`meta`** (§3, §6): what else the host tells of an entity or a word (a label, a unit, the type of value an entity takes), for editors and agents.

## Core

- **Core** (§21): the level everything stands on: typed cells, signals and ports and the hub that commits them; no names, no JSON, no principals. `package:parlance/core.dart`.
- **Hub** (§21.1): commits the writes and emits of its cells and signals in ticks, numbers them with seq; `batch`, `onCommit`, `ticks`.
- **Tag** (§21.1): what a writer gives with a write or an emit, carried unread into the tick; the registry carries causes in it.
- **Cell**, **keyed cell** (§21.2): one value, or one value per key, with one writer (`claim`), `watch` from the value now.
- **Signal** (§21.3): said once, no value kept; one emitter unless open.
- **Port** (§21.4): one handler (`serve`) answers `call`.
- **Interfaces** (§21.6): `IStateReader`, `IStateWriter`, `ICommandCaller`, `IFactEmitter`, `IFactListener`: what both the core's handles and the registry's typed handles are, so code on them moves from one to the other unchanged.

## Who and why

- **Principal** (§4): who acts, a `kind` and an `id` (`user/local`, `plugin/hydra`, `viewer/twitch/123`). Kinds are the host's; the package reserves `system` (the registry).
- **Selector** (§6.2): how callers and readers name principals: a kind (`user`), a kind and id (`plugin/hydra`), or `*`. The most specific one that matches wins.
- **Cause** (§4): why a message happened: `by` (the principal) and `parent` (the message it follows from). Passed explicitly: `call.causeFor(by)`.
- **Overrider** (§9): a principal kind the host allows to override an overridable denial (`Registry(overriders: {...})`).

## Words

- **Word** (§6): a name in the registry with its type and rules: a state, a command or a fact. A host's words are its vocabulary, the API every client speaks. A state is written by its owner only; a command asks the owner.
- **Descriptor** (§6): a word's description: `StateDescriptor`, `CommandDescriptor`, `FactDescriptor`.
- **State** (§6.1): something that is so now; read, watched, written by one writer.
- **Keyed state** (§6.1): one value per key (`audio.gain[mic]`); an unkeyed state holds one value.
- **Writer**, **write handle** (§6.1): who defined a state holds its only write handle (`RawStateWriter`, typed `StateWriterOf<T>`).
- **Readers** (§6.1, §6.3): which principals may read a state or hear a fact over remote and to agents; none means everyone. Code in the registry's process reads everything. `mayRead`, and `unreadable` in `describeFor`.
- **Command** (§6.2): something that can be asked: params, an optional answer (`returns`), exactly one handler.
- **Handler** (§6.2): the code that runs a command; gets the call (`CommandCall`, typed `CommandCallOf<P>`).
- **Callers** (§6.2): selectors with `allow`, `warn` or `deny`; who matches none is denied.
- **`warn`** (§6.2): allowed, but an editor tells the author who can now call it (any viewer, say).
- **Deadline** (§6.2): how long a handler may take before the call is `timedOut`; 30 s by default.
- **Availability** (§6.2): the owner's synchronous check that a command can run now, with a reason when it cannot. `whyUnavailable(command)` asks without calling, so a button can be grey with the reason.
- **Fact** (§6.3): something that happened, said once, with no value that stays.
- **Open fact** (§6.3): one the host lets several producers say (the chat of several platforms); more emit handles are handed out.
- **Emit handle** (§6.3): what says a fact (`RawFactEmitter`, typed `FactEmitterOf<T>`).
- **Producer** (§6.3, §14): who says a fact: its definer, or one handed an emit handle of an open fact.
- **Dedup window** (§6.3, §9): how long an id answers its first message: a fact seen again is dropped, a call seen again answers the first result.
- **Catalog** (§6.4): the descriptors and entity kinds there are now; changes at runtime (`catalogChanges`).
- **`describe`**, **`describeFor`** (§6.4, §14): the catalog as JSON; for a principal, with what it may call (`access`), what cannot run now (`unavailable`) and what it may not read (`unreadable`).
- **Word status** (§6.5): whether a principal can use a word now: `WordMissing`, `WordNotPermitted`, `WordUnavailable(why)`, `WordReady`; `statusOf`, `statusChanges`, and the same on a view.
- **Alias**, **old name** (§6.4): a renamed word's former name, standing for it everywhere (`alias(old, now)`, `canonical(name)`, `aliases` in `describe`); not a word itself.
- **Withdraw** (§6.4): giving a word up by disposing its handle; waiting calls of a withdrawn command end `unknownCommand`.

## Time and order

- **Message** (§5): a committed state change or fact; each has an id.
- **Id** (§5): 128 random bits as hex, unless the sender gives one; over remote, ids are per principal.
- **Epoch** (§5): the id a registry takes when it starts; seq numbers compare only within one.
- **Seq** (§5): the sequence number every committed change and fact gets; a total order consistent with causality.
- **Tick** (§7): the unit of change: what was written and said together, committed together, delivered as one `Tick {epoch, from, to, changes, facts}`. Observers never see half a tick.
- **Batch** (§7): `registry.batch(fn)` makes everything `fn` writes one tick; batches nest. Inside, reads see the batch's own writes.
- **State change** (§7): one entry of a tick: the state, the key, the value and the one before, removed or not, its cause.
- **Feed** (§12): the registry as a stream for remote clients and journals: a snapshot (or the retained ticks after a known seq), then live ticks.
- **Snapshot** (§12): every state value with the epoch and seq; `factsLost` after a gap.
- **Retained ticks** (§12): the last ticks the registry keeps (1000) for a feed to resume from; and the last facts per name (100) for `recent`.
- **`recent(fact, n)`** (§12): the last facts of a name the registry keeps.
- **Watch** (§6.1): a state's value now, then on every change (`registry.watch`).

## Calls

- **Call** (§9): `call(name, params, by:, id?, override?)`. Stages, the first refusal ends it: dedup, lookup, params, policy (callers), availability, guards, handler.
- **CallResult** (§9): how a call ended: `done(value)`, `refused(code, reason, guard?)`, `failed(error)`, `timedOut`, `lost(id, reason)`. Data, not exceptions. `whyNot` tells any end but `done` in words.
- **Refusal codes** (§9): `unknownCommand`, `invalidParams`, `notPermitted`, `unavailable`, `denied`, `idConflict`.
- **`failed`** (§9, §19): the handler said no (`failCall(why)`, a `CallFailure`) or threw, or its answer did not pass `returns`.
- **`timedOut`** (§9): no answer within the deadline. Not an end: the handler is told (`call.expired`); what it then does stands, and its end comes as a second call record marked `late`.
- **`lost`** (§9, §14): the answer did not come back over remote; whether it ran is unknown, and a retry with the id runs it at most once.
- **Override** (§9, §10): a call that goes past an overridable denial, by a principal whose kind may; its record says so.
- **Call record** (§9): every finished call (request, cause, stages passed, result, override, timings) on `registry.calls`, for journals. `callStarts` tells a call as its handler begins (`CallStarted`), `running` the ones in flight now.
- **Guard** (§10): a synchronous check asked on every call that reaches its stage; returns a denial reason or nothing. **Overridable** unless it says not.
- **Log, span** (§9.2): `Registry(log:)`, a `LogScope` of rpc_dart's logger, `noop` unless given: then nothing is logged or made. Each call a span whatever the level (nested calls its children, one trace, across a connection too; a call answering a fact or an ended call links that span); refusals, ticks, the catalog and errors by level, constant messages with their fields in `data`. A handler logs in `call.span`.
- **Explanation** (§9, §16): why a state is as it is: its last change, on whose behalf, and the calls that led to it (`registry.explain`, `why`). `forgotten` and `trailCut` say what is no longer kept.

## Typed words (§18)

- **IStateWord<T>**, **ICommandWord<P, R>**, **IFactWord<T>**: a word's name with its Dart types; a host's enum of its words implements them, so no name or param key is typed twice.
- **Shape**: how a JSON value is a Dart one, and the registry type it gives: `Plain`, `EnumShape`, `ListShape`, `MapShape`, `Nullable`, `RecordShape` (an object as a record), `UnionShape` (one of several objects as a sealed class).
- **Part**: a field of a `RecordShape`: its shape, optional or default, description.
- **`RecordShape.none`**: the params of a command that takes none.
- **Typed handles**: `StateOf`, `StateWriterOf`, `CommandOf`, `CommandCallOf`, `FactOf`, `FactEmitterOf`, `Fact<T>`; through `registry.state(word)`, `command(word)`, `fact(word)`.
- **The word fixes the types**: a call is made on what `command(word)` gives, never by a generic function taking a word and params together, which would compile another command's params.

## Owners (§19)

- **Owner**: who defines words and does their work. `define(r)` defines them through typed words and `keep`s each handle; `sync()` writes the states as its devices or ports have them now; `dispose()` withdraws them, the last kept first.
- **Attaching owners**: `p.attach({name: owner})`, each to the part of its name; the participant holds them, `p.sync()` syncs them all in one batch (one tick), `p.dispose()` takes them with it.
- **Scope** (§19.2): a participant with its owners `main` makes for a while (a user's session, a feature) and disposes, all it held going with it; an owner's `changes` syncs it on its own.
- **TestHost** (§24): a registry for a test with stand-ins for the modules it leaves out (`stateOf`, `commandOf`, `factOf`) and what happened read back (`written`, `said`, `callsOf`).
- **Word use** (§6.8): who used a word, by the name used: calls and asks, remote subscriptions, reads from outside the build (`usesOf`, `usage`, `WordUse`); bounded by `usersPerWord`.
- **IWord**: a word of any kind by its name; every typed word is one.
- **Vocabulary** (§23): a module's words as an abstract class, `@Vocabulary(namespace)`; `parlance_generator` makes its typed enums. `schemaOf` / `schemaBreaks`: the schema it keeps and what changed of it.
- **Handles**: the set of handles an owner keeps, withdrawn together.
- **`keep`**: keeps a handle and gives it back with its own type.
- **`trackKind`**: registers a kind of entities the owner keeps; its sync announces `entitiesChanged` only when the list changed, and answers the ids that went, whose keyed values the owner removes.
- **`listen`**: a subscription that lives while the owner is attached, for what its work reports by itself.
- **`failCall(why)`**: ends a call `failed` with the owner's reason; refusals with a code come only from the registry's stages.

## Remote (§14)

- **Session**: one connection with one principal, fixed by the host when it accepts it: a participant the host made and serves on it (`participant.serve(endpoint)`, a `RemoteSession`, one per connection). Its words go with it.
- **`RemoteSession`**: the registry's side of a session: `hears`, `close`.
- **Remote participant** (`RemoteParticipant`): a part across a connection, the only way across; the registry calls its commands over the same connection.
- **Parent** (§14): the call a session is serving, or a fact the registry keeps, that what it does follows from.
- **Subscription**: the states and facts a session's feeds carry (`subscribe`); a tick with none of them is not sent, without leaving a gap. `values` items bring what a new subscription adds.
- **`hears`**: whether a session's feeds carry a fact matching a test: what the host knows a participant learns.
- **Protocol**: the remote protocol's version, told by `describe`.
- **Mirror**: a remote participant's copy of the states it follows, from the feed; resumes after a lost connection, back to a snapshot after a gap. The package's own.
- **Synced**: whether a mirror follows the registry now.
- **`reach(epoch, seq)`**: waits until a mirror has a call's seq, so a read after a call reads its effect.

## View (§20)

- **IRegistryView**: what a screen reads and calls: values now, told when the states it draws change (`changes`), facts said from now on, `recent`, calls on behalf of one principal, `synced`.
- **LocalView**: a view of a registry in the same process, as one principal.
- **fetch** (§20): a read by name of a state a view may not keep; across a connection kept from then on.

## Agents (§16)

- **Agent**: a participant the MCP tools work on, here or across a connection.
- **`parlanceTools`**: the curated tools: `describe`, `read`, `call`, `recent_facts`, `why`; with `commandTools`, a tool per command too.
- **`McpTool.typed`**: a host's own tool, its JSON Schema derived from a `RecordShape`.
- **`McpSocketServer`**: agents on a Unix socket (`mcp_io.dart`); `toolsChanged()` reaches every session.
- **`parlance-mcp`**: an agent's participant across a connection as a stdio server.
- **Participant** (§22): a part of the app as it speaks, through `IParticipant`: one principal (`who`), words defined only in its `namespaces`, written and said as itself; made by `main` (`registry.participant`), so the part never holds the registry.
- **Namespace** (§22.1): the first words of the names a participant may define (`orders` for `orders.cancel`); one live participant's alone.
- **Participant rights** (§22.2): `define` (a further check on its words), `produce` (open facts of others), `speakFor` (facts on someone's behalf).
- **Access by default** (§22.2): `WordAccess(read:, call:)`, the readers and callers of a participant's words when a word does not say; a word's own replaces it whole.
- **Part** (§4, §22.3): `principal.child(name)` (`studio/sound`), and a participant's `child(name)` speaking as it; a part has its whole's rights unless named itself, and its acts are told as its own, for audit.
- **Version** (§1): a word's breaking change beside the old one, the same name with `.v<N>` (N >= 2); the name alone is version 1. A version is a word of its own; `wordVersion(name)` parses one.
- **Query** (§6.6, §18): a word that only answers, a kind of its own (`QueryDescriptor`, `is: query`; `IQueryWord`, asked with `.ask`): no dedup, no call record, nothing changed from its handler; safe to ask again.
- **JsonShape** (§18): the shape of a class that serializes itself (json_serializable, freezed), with an optional `type` for checks and `describe`.
- **QueryEffect** (§6.6): what a query's handler tried that would change something (a write, a fact, a command), refused where it was tried; the handler runs marked as the query's (`asQuery`).
