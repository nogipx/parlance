---
name: switchboard
description: Write, change, review and test code that uses or extends the switchboard package (package:switchboard; libraries registry, links, remote, mcp): defining states, commands and facts with their callers, passing causes, writing links (reactions, bindings, constraints, interceptions, own words), who may call what and why a call was refused, remote sessions and the MCP board. Use whenever code imports package:switchboard, touches packages/switchboard, or a task asks why a command was refused, who a link acts for, or how to add something to the registry.
---

# switchboard

A registry of **states** (one owner writes, everyone reads), **commands** (one handler, a params schema, who may call) and **facts** (what happened), plus **links** between them. Participants know only the catalog, never each other; `main` wires them.

The contract the code and its tests follow is in `references/`, one file per library; read only the one a task needs. `SPEC §n` in the code is section n there. Where code and contract disagree, the contract is fixed first, then the code. Version 0.1 (draft).

| Library | What it is | Contract |
|---|---|---|
| `registry` | catalog, writes in ticks, calls, layers, guards, hooks, feed, format versions, typed words | [references/registry.md](references/registry.md): §1–12, §17, §18 |
| `owners` | `Owner`, `Owners`, `Handles`, `TrackedKind`, `failCall`: defining, syncing and withdrawing a host's words | [references/owners.md](references/owners.md): §19 |
| `links` | the engine of links and own words, on the registry's public API | [references/links.md](references/links.md): §13, §15 |
| `remote` | the registry over rpc_dart: one session per connection | [references/remote.md](references/remote.md): §14 |
| `mcp` | curated agent tools on a `Board` (local or remote); the binary `switchboard-mcp` | [references/mcp.md](references/mcp.md): §16 |

## Adding to the registry

A host names its words once, typed (SPEC §18), and never types a name or a param key elsewhere:
- **Words:** an enum per owner, `enum XState<T> implements StateWord<T>`, `enum XCommand<P, R> implements CommandWord<P, R>`, `enum XFact<T> implements FactWord<T>`; each value its name and shape. Params and objects are records with a `RecordShape(fields, to:, from:)`; enums are `EnumShape(values)`; no params is `RecordShape.none`.
- **Owner:** a class `extends Owner` (`package:switchboard/owners.dart`): words in `define(r)`, each handle through `keep(...)`, states written in `sync()`, entity kinds by `trackKind`; a port that says no ends the call with `failCall(why)`; `Owners(registry, [...])` attaches them and syncs them as one tick.
- **State:** `r.state(XState.a).define(by: owner, meta:)` returns the only `StateWriterOf<T>`. A settable state has one command with `sets: Sets(XState.a.name, value: 'param', key:?)`.
- **Command:** `r.command(XCommand.b).define((c) => ..., callers:, sets:?, interceptable:?, deadline:?, available:?)`; `c.params` is the record. `available` answers why it cannot run now (shown before anyone calls).
- **Fact:** `r.fact(XFact.c).define(by: producer)`; `emit(record, cause:)`.
- **Call and read:** `r.command(XCommand.b).call(params, by:)` answers `CallResult<R>`; `r.state(XState.a).read()`, `.watch()`; `r.fact(XFact.c).stream`. Never a generic helper taking a word and params together: it loses the types (SPEC §18).
- The string API (`defineState(StateDescriptor(...))`, `call(name, map)`) is for names known only at run time: own words, links, remote, MCP.
- **Callers** decide who may call: selectors `kind:id`, `kind`, `*`; the most specific wins; unmatched is denied; `warn` allows but tells editors. In Tephra use `Who.crew`, `Who.crewAndViewers`, `Who.streamerAtTheMac`.
- **Causes:** inside a handler, write and call with `cause: call.causeFor(owner)`, so the trail shows which call led to it. Never pass causes through zones.
- Names are dotted lowercase (`audio.muted`); never two owners for one name.

## Why a call was refused

Stages, first refusal wins (SPEC §9): dedup by id (`idConflict` if the id was given to another call) → command exists → params (`invalidParams`) → callers (`notPermitted`) → `available` (`unavailable`) → guards (`denied`, with the guard id) → before hooks → handler (`failed`; `timedOut` means *no answer yet*, the work may still finish). A guard marked overridable is passed only with `override: true` by a kind in `Registry.overriders` (Tephra: `user`, `remote`). `why`/`explain` and the call records tell what happened.

## Links

- Shapes, triggers, steps: `linkGuide` in `lib/src/link_words.dart` (a test holds it to the parser). The engine's words are `LinkWords`, typed (`LinkWords.press` is a `CommandWord<PressLink, LinkOutcome>`); never type `'links.…'` elsewhere.
- A host's links in Dart: `XCommand.b.step(params)`, `XState.a.flip()`, `XState.a.holds(value)`, `XFact.c.trigger()`, `XState.a.becomes(value)` (SPEC §13.11). Over remote: `client.command(word).call(...)`, `mirror.state(word).read()`.
- A whole host in miniature: `example/` (run `fvm dart run example/main.dart`).
- **Who a run acts for:** a press acts for the presser; a fact or state change caused by someone *outside the engine's managers* acts for them (their rights, never the link's); anything else acts as `link:<id>`. So a viewer reaches only what names viewers in its callers.
- **Own words** (`my.*`): callable by the managers; a definition's `callers` only add more. A viewer may call one only if it says so explicitly.
- A firing that does not run spends no `once`, throttle or rate. Statuses (`links.status`) say why a link is unresolved, disabled or failing.
- The host's links come from `source(name, defs)`; the user's own from a `LinksStore`, saved before they apply.

## Remote and agents

- A session's principal is fixed by the host when it accepts the connection; call ids are per principal.
- Remote outcomes are data: `CallLost(id)` when the answer did not come back (retry with the id), `BoardOffline` while disconnected, `BoardBehind` when the mirror has not caught up with your call.
- MCP tools are curated (`switchboardTools`); a host adds its own and must call `McpSession.toolsChanged()` whenever its tools change.

## Rules of the package

- Imports go one way: `links`, `remote` and `owners` use `registry`; `mcp` may import only `link_words.dart` from links, and that file only the registry's types and words; only `remote` uses rpc_dart. `test/boundaries_test.dart` holds this.
- No words of any domain in `lib/` (the boundary test bans them); the host's vocabulary stays in the host.
- Results are typed (`CallResult<R>`, `Explanation`, `LayerInfo`); serialize at the edges.
- `contract.g.dart` is generated: change `contract.dart`, then `fvm dart run build_runner build`.
- A behavior change updates the contract in `references/` in the same change.

## Testing

- Fixtures: `test/registry/fixture.dart` (`Fixture`, principals `user`, `agent`, `viewer`, `owner`), `test/links/fixture.dart` (`LinksFixture`, `use(defs)`, `stateOf(id)`).
- Time: `fakeAsync(..., initialTime: DateTime(...))` whenever wall-clock triggers (`at`) are involved; the registry reads time from its `clock`.
- Name tests after the promise they hold ("a firing that does not run spends no once"); `test/links/promises_test.dart` is the model.
- Run: `fvm dart test` in `packages/switchboard`; `fvm dart analyze`.
