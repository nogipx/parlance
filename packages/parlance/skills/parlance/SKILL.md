---
name: parlance
description: Write, change, review and test code that uses or extends the parlance package (package:parlance; libraries registry, links, remote, mcp): defining states, commands and facts with their callers, passing causes, writing links (reactions, bindings, constraints, interceptions, own words), who may call what and why a call was refused, remote sessions and the MCP board. Use whenever code imports package:parlance, touches packages/parlance, or a task asks why a command was refused, who a link acts for, or how to add something to the registry.
---

# parlance

A registry of **states** (one owner writes, everyone reads), **commands** (one handler, a params schema, who may call) and **facts** (what happened), plus **links** between them. Participants know only the catalog, never each other; `main` wires them.

The contract the code and its tests follow is in `references/`, one file per library; read only the one a task needs. `SPEC §n` in the code is section n there. Where code and contract disagree, the contract is fixed first, then the code. Version 0.1 (draft).

| Library | What it is | Contract |
|---|---|---|
| `core` | cells one writer writes, signals, ports one handler serves, the hub that commits them in ticks; typed, no names, no JSON, no dependencies. Everything below is built on it; a small task takes it alone | [references/core.md](references/core.md): §21 |
| `registry` | catalog, writes in ticks, calls, layers, guards, hooks, feed, format versions, typed words | [references/registry.md](references/registry.md): §1–12, §17, §18 |
| `links` | the engine of links and own words, on the registry's public API | [references/links.md](references/links.md): §13, §15 |
| `remote` | the registry over rpc_dart: one session per connection | [references/remote.md](references/remote.md): §14 |
| `participant` | `IParticipant`: a part of the app as one principal, defining words only in its vocabularies' namespaces and holding its owners (`Owner`, `TrackedKind`, `failCall`; contract §19 in [references/owners.md](references/owners.md)), the same in this process (`LocalParticipant`) and across a connection; rights to produce and speak for others | [references/participant.md](references/participant.md): §22 |
| `view` | `IRegistryView`: what a screen reads and calls, one interface over a registry in this process (`LocalView`) or a `RegistryMirror` (`MirrorView`) | [references/view.md](references/view.md): §20 |
| `schema` | a module's words written once as an abstract class (`@Vocabulary`), from which `parlance_generator` makes the typed enums and shapes; `schemaOf` / `schemaBreaks` keep published words from changing by accident | [references/schema.md](references/schema.md): §23 |
| glossary | every term of the package in a line, with its section | [references/glossary.md](references/glossary.md) |
| `mcp` | curated agent tools on a `IBoard` (local or remote); `mcp_io`: the server on a Unix socket; the binary `parlance-mcp` | [references/mcp.md](references/mcp.md): §16 |

## Adding to the registry

A host names its words once, typed (SPEC §18), and never types a name or a param key elsewhere:
- **Words, generated:** write them once as an abstract class marked `@Vocabulary('orders')` (`package:parlance/schema.dart`), members marked `@StateWord`, `@CommandWord`, `@QueryWord`, `@FactWord`, bounds by `@Range`, `@Length`, `@Ref`; `parlance_generator` makes the enums below, the params records, the vocabulary `<class>Words` (a `WordSet`: its namespace and words; `main` grants it, `registry.participant(who, vocabularies: [ordersWords])`, so the namespace is written once) and the owner base `<Class>Owner`: extend it and write only the handlers (`setVolume(CommandCallOf<...> call)`, writing with `cause: call.inReply`) and `sync()`; it says each fact by a method of its params (`clipped(volume: 95)`); one vocabulary is one namespace; `sets`, `callers`, `available` and the rest are said in the annotations (SPEC §23.4). A consumer takes `<Class>Client(view)`: states as getters and `...Changes` streams, commands and queries as methods of the class's params that throw `CallNotDone` when not done, facts as streams of `Fact<T>` (SPEC §23.5). Keep `schemaOf(ordersWords.words)` in the repository and test `schemaBreaks(before, now)` is empty.
- **Words:** an enum per owner, `enum XState<T> implements IStateWord<T>`, `enum XCommand<P, R> implements ICommandWord<P, R>`, `enum XFact<T> implements IFactWord<T>`; each value its name and shape. Params and objects are records with a `RecordShape(fields, to:, from:)`; enums are `EnumShape(values)`; no params is `RecordShape.none`.
- **Owner:** a class `extends Owner` (`package:parlance/participant.dart`), code only: words in `define(p)` through the participant it is attached to (SPEC §22), no `by`; `main` makes the participant (`registry.participant(who, vocabularies: [ordersWords], rights:, access:)`) and attaches the owners to it (`p.attach({'sound': Mixer(), ...})`: each speaks as its part, `studio/sound`, for audit); each handle through `keep(...)`, states written in `sync()`, entity kinds by `trackKind`; a port that says no ends the call with `failCall(why)`; `p.sync()` syncs them as one tick; an owner that gives `changes` (a stream told when its model moved) is synced on its own. A participant is a scope: made when a user signs in or a feature opens, disposed when it ends, its owners, words, values, kinds and declarations going with it (SPEC §19.2). What it owns it may list in `words` (`[...XState.values, ...]`, each inside its namespaces; `describe` tells it under `declared`, SPEC §6.7); what an owner needs of others it says in `uses` (`Use.required(word)`, `Use.optional(word)`); once all participants have their owners `main` awaits `p.checkUses()`, which throws `UnmetUses` naming each required word missing or not permitted (SPEC §19.1).
- **State:** `r.state(XState.a).define(by: owner, meta:)` returns the only `StateWriterOf<T>`. A settable state has one command with `sets: Sets(XState.a.name, value: 'param', key:?)`.
- **Command:** `r.command(XCommand.b).define((c) => ..., callers:, sets:?, interceptable:?, deadline:?, available:?)`; through a participant `callers` may be left to its `access.call`; a word that only answers is a query, a kind of its own (SPEC §6.6, `QueryDescriptor`; `defineQuery` for names known at run time): `enum XQuery<P, R> implements IQueryWord<P, R>`, `r.query(XQuery.c).define((q) => ..., askers:?)`, asked with `.ask(params)` (no sets, hooks, dedup or call record; askers default as readers); its handler gets a `QueryAsk`, and a write, fact or command call from it is refused (`QueryEffect`), so put nothing that changes the world in a query, not even past parlance; `c.params` is the record. `available` answers why it cannot run now (shown before anyone calls).
- **Fact:** `r.fact(XFact.c).define(by: producer)`; `emit(record, cause:)`.
- **Call and read:** `r.command(XCommand.b).call(params, by:)` answers `CallResult<R>`; `r.state(XState.a).read()`, `.watch()`; `r.fact(XFact.c).stream`. Never a generic helper taking a word and params together: it loses the types (SPEC §18).
- **Is a word there for me:** `view.status(word)` / `statusChanges(word)` (`registry.statusOf(name, by:)`): `WordMissing`, `WordNotPermitted`, `WordUnavailable(why)`, `WordReady` (SPEC §6.5). An absent word never fails a read or a listener; ask its status instead of checking the catalog once at start.
- The string API (`defineState(StateDescriptor(...))`, `call(name, map)`) is for names known only at run time: own words, links, remote, MCP.
- **Callers** decide who may call: selectors are `*` or a path split by `/` only (`user`, `plugin/hydra`, `viewer/twitch`, `module/orders/sync`); a selector names all under it, the nearest said wins; a level holds letters, digits, `.`, `-`, `_` only, all else reserved (a selector or principal with another sign is refused; make a level of an outside id with `Principal.levelOf`); unmatched is denied; `warn` allows but tells editors. In Tephra use `Who.crew`, `Who.crewAndViewers`, `Who.streamerAtTheMac`.
- **Causes:** inside a handler, write and call with `cause: call.causeFor(owner)`, so the trail shows which call led to it. Never pass causes through zones.
- Names are lower-case words split by `.`, joined within by `_` only (`audio.voice.muted_talk`, never `muted-talk`); never two owners for one name.

- **Words are a public API.** The user's links, plugins and agents name them. Never rename one bare: keep the old name with `registry.alias(old, now)` so what named it keeps working, and ask `links.uses {word}` (`link_uses`) who names it before changing it.

## Why a call was refused

Stages, first refusal wins (SPEC §9): dedup by id (`idConflict` if the id was given to another call) → command exists → params (`invalidParams`) → callers (`notPermitted`) → `available` (`unavailable`) → guards (`denied`, with the guard id) → before hooks → handler (`failed`; `timedOut` means *no answer yet*, the work may still finish). A guard marked overridable is passed only with `override: true` by a kind in `Registry.overriders` (Tephra: `user`, `remote`). `why`/`explain` and the call records tell what happened.

## Links

- Shapes, triggers, steps: `linkGuide` in `lib/src/link_words.dart` (a test holds it to the parser). The engine's words are `LinkWords`, typed (`LinkWords.press` is a `ICommandWord<PressLink, LinkOutcome>`); never type `'links.…'` elsewhere.
- A host's links in Dart: `XCommand.b.step(params)`, `XState.a.flip()`, `XState.a.holds(value)`, `XFact.c.trigger()`, `XState.a.becomes(value)` (SPEC §13.11). Over remote: `client.command(word).call(...)`, `mirror.state(word).read()`.
- A whole host in miniature: `example/` (run `fvm dart run example/main.dart`).
- **Who a run acts for:** a press acts for the presser; a fact or state change caused by someone *outside the engine's managers* acts for them (their rights, never the link's); anything else acts as `link/<id>`. So a viewer reaches only what names viewers in its callers.
- **Own words** (`my.*`): callable by the managers; a definition's `callers` only add more. A viewer may call one only if it says so explicitly.
- Buttons: `links.controls()` (shown, `lit`, `unavailable`) and `registry.pressLink(id, by:)` (SPEC §13.12); a call's end in words: `result.whyNot`.
- A firing that does not run spends no `once`, throttle or rate. Statuses (`links.status`) say why a link is unresolved, disabled or failing.
- The host's links come from `source(name, defs)`; the user's own from a `ILinksStore`, saved before they apply.

## Remote and agents

- A session's principal is fixed by the host when it accepts the connection; call ids are per principal. Both sides are `RpcPeerEndpoint`s: `RegistryResponder(endpoint, registry, principal:, vocabularies:, rights:)` (a plugin's: `[WordSet.open(id)]`, its words come at run time) on the host's, a session being a participant (SPEC §22).
- **A remote part is a participant too:** `await RemoteParticipant.join(connection)`, always over an `RpcClientConnection` (it rejoins after a drop; a fixed connection, wasm or memory, is one that does not reconnect), gives the same `IParticipant` as in the host's process, so an `Owner` attaches to it unchanged (`owner.attach(p)`). What it asks goes in order, one turn as one tick; refusals come to `errors`; `flush()` waits for the host. It reads another's state only while it watches it.
- The lower level stays: `ParlanceClient(endpoint)` (`client.define`, `client.write`, `client.emit`) and a `RemoteOwner` serving its commands; pass `parent: call.id` (or a fact's id) so what it does follows from what it answers. Its words go with the session.
- A participant that needs a few states and facts subscribes: `mirror.subscribe(states: {...}, facts: {...})`; its feed then carries only those, without gaps, and the host knows what it hears (`session.hears`).
- Remote outcomes are data: `CallLost(id)` when the answer did not come back (retry with the id), `BoardOffline` while disconnected, `BoardBehind` when the mirror has not caught up with your call.
- MCP tools are curated (`parlanceTools`); a host adds its own and must call `McpSession.toolsChanged()` whenever its tools change.

## Rules of the package

- Imports go one way: `links`, `remote` and `owners` use `registry`; `participant` uses `registry` and the view interface (`view/view.dart`), never remote; `owners` use `participant` too; `mcp` may import only `link_words.dart` from links, and that file only the registry's types and words; only `remote` uses rpc_dart. `test/boundaries_test.dart` holds this.
- No words of any domain in `lib/` (the boundary test bans them); the host's vocabulary stays in the host.
- Results are typed (`CallResult<R>`, `Explanation`, `LayerInfo`); serialize at the edges.
- `contract.g.dart` is generated: change `contract.dart`, then `fvm dart run build_runner build`.
- A behavior change updates the contract in `references/` in the same change.

## Testing

- Fixtures: `test/registry/fixture.dart` (`Fixture`, principals `user`, `agent`, `viewer`, `owner`), `test/links/fixture.dart` (`LinksFixture`, `use(defs)`, `stateOf(id)`).
- Time: `fakeAsync(..., initialTime: DateTime(...))` whenever wall-clock triggers (`at`) are involved; the registry reads time from its `clock`.
- Name tests after the promise they hold ("a firing that does not run spends no once"); `test/links/promises_test.dart` is the model.
- Run: `fvm dart test` in `packages/parlance` (four files at a time, `dart_test.yaml`), or only the files a change touches; `fvm dart analyze`.
