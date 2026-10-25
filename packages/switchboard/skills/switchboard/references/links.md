# switchboard contract: links (§13, §15)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. Where code and contract disagree, the contract is fixed first.

## 13. Links

Links are data. The engine validates them against the catalog; a link that names something the catalog lacks is **unresolved** and inactive until the catalog has it (a plugin may start later).

### 13.1 Own words

- **Own command** `my.<name>`: params, steps, callers (the engine's managers always; a definition's `callers` open it to more, and only an explicit `callers` lets anyone outside the managers in). Registered as a command whose handler runs the steps on behalf of `link:<id>`.
- **Own state** `my.<name>`: `bool` or `enum`, with a default and a setter `my.<name>.set { value }`, callable by the managers (and the registry, for layers). Its values are the engine's to persist.

### 13.2 Triggers

| Kind | Fires |
|---|---|
| `fact` | a fact with the name, whose payload matches the filter |
| `state` | a state (and key) `becomes` / `leaves` a value, or `changes` (optionally `from` → `to`); `for` — and stays so that long |
| `every` | every interval, from when the link activates |
| `at` | at a local time of day, on the given weekdays |
| `manual` | `links.press { link, args?, wait? }`; the presser is the principal. With `wait`, the answer comes when the run has ended, with its `failure` if it stopped early |

A state trigger fires on a **change** of a value only. A value that comes where there was none (a state defined later, a new key, the first value) and one that goes (removed) are no change: `becomes`, `leaves` and `changes` do not fire for them, so a word coming with a plugin or a new entity does not set off links as if something had happened. **`already: true`** (with `becomes`, `leaves` or `changes.to`) fires it too for what already holds: once when the link starts (every key that holds, each on its own), and for a value that comes holding; with `for`, it must go on holding that long from then.

Options on any trigger: `throttle` — at most once per interval, per key (a path into the trigger, e.g. the viewer); `once` — once until `links.reset { link }`. The host registers **trigger extensions**: a name, a translation to one of the kinds above, and a parse of the extension's own options; the package knows none. The throttles an extension's translation carries are defaults (a chat command's cooldown, so a busy chat cannot run a link past its rate): a `throttle` in the definition replaces them.

The principal of a run is the presser for `manual`; the principal an extension gives (a viewer, for a chat command); for a fact or a state change, whoever caused it when the engine's managers do not count them in; else `link:<id>`: time, the managers' own actions, own commands and interceptions run on behalf of the link (§13.5).

### 13.3 Conditions

Over committed state only: `is`, `not`, `in`, `<`, `<=`, `>`, `>=`; a list means all, `any` means at least one. No facts, no branches.

The engine keeps its own view of the state, built by applying ticks in seq order. Conditions of triggers, bindings and waits read the view **as of the tick being handled**, never state committed after it: a fact is judged by the state at its position in the log. A press reads the registry at the time of the press; constraints read it at the time of the call; steps read it when they run.

### 13.4 Steps

`call` (a command, own ones too), `flip` (a bool state through its setter), `wait`, `waitUntil` (a fact or a condition, with a timeout; on timeout the run stops unless `orContinue`), `temporarily` (calls whose commands have `sets` become layers for `for` or `until`; other calls run once).

Params are values, references (`$trigger.<path>`, `$state.<name>[<key>]`) and string templates (`"{from} raided"`). No arithmetic, variables or `if`.

### 13.5 Reactions

Trigger(s) → conditions → steps. Mode when it fires while running: `single` (skip; default), `restart` (cancel the running one, its layers drop), `queue` (with a limit; default 10). A run lasts until its steps and its temporaries end. A refusal stops the run unless the step says `orContinue`. A run is not a transaction: what its steps did before stays done, and the link's status and the run's `failure` say which step stopped it and that those before it were done (`step 2 of 3, after step 1 done: …`).

**On whose behalf a run acts.** A press acts for the presser. A fact or a state change acts for whoever caused it (its cause's principal) when the engine's managers do not count them in: their rights, never the link's, so they reach only what names them in its callers. Every other trigger (the managers' own actions, timers, the registry) runs as the link, `link:<id>`, with no more rights than the link has. An extension's `accept` may name the principal itself.

A firing that does not run (conditions, mode, a full queue, a throttle, `once`) spends nothing: no throttle, no `once`, no count toward the rate limit. Runs dropped from a queue end as `stopped`, so a press that waits for one is answered. A run that ends well clears the failure its link's status showed.

### 13.6 Bindings

While the conditions hold, push one layer per held call (only commands with `sets`), owner `link:<id>`, with the link's priority; when they stop, drop them. A binding whose layer was dropped as `overridden` does not push it again until its conditions turn false and then true. A binding changed while it holds pushes its new layers before it lets go of the old ones, so a held value moves straight to the new one, never through the value under it. After a restart (the registry's layers imported), a binding takes back its own layers when it starts: held on by the ones it pushes, or let go at once when its conditions are false, so the base from before the restart comes back. Layers imported after the engine started are taken back by `takeBackLayers()`, the same way. An **anchor** gives a binding its condition and its home: the host registers anchor kinds (an entity kind and the condition an entity makes); the binding names the entity.

### 13.7 Constraints

A guard: a target (a command with a param filter, every command of a namespace, or every command), the principals it applies to (default: everyone), conditions, the principals it applies to, a reason. Overridable unless it says otherwise.

### 13.8 Interceptions

A before hook on an interceptable command: steps, a priority and a required timeout.

### 13.9 Safety

- Loops: a link never fires for a message whose chain holds its id.
- Rate: a link that fires more than 20 times a minute is disabled and the engine emits `links.disabled { link, reason }`.
- Time: the registry reads time from its `clock` (given, or the zone's clock when it was made) and waits with `Timer`, so tests run time by hand with `fake_async`.
- Trials: `links.try { link }` runs a reaction with a made-up trigger, or checks a constraint, with `test` set in the cause.

### 13.10 What the engine takes

The engine takes names in the registry: the states `links.status`, `links.controls` and `links.own`, the fact `links.disabled`, the commands `links.*`, the entity kind `link`, the principal kind `link` (it acts as `link:<id>`, `linkPrincipal(id)`) and the prefix `my.` of own words. So one engine runs on one registry; a second one is refused by the registry as a name defined twice.

These names are `LinkWords` (`lib/src/link_words.dart`, with `linkGuide`, how links are written). It imports nothing: a client of the engine (the agent's tools, a host's buttons) calls the engine by them without importing the engine. A test holds `linkGuide` to the keys the parser reads.

**Who names a word.** `links.uses { word }` (and `Links.uses(word)`) answers every link that names a state, a command or a fact, and how: `trigger`, `condition`, `call`, `flip`, `reads` (a `$state` reference), `waits`, `holds` (a binding), `guards` (a constraint), `intercepts`; every link composed, active or not, own commands' steps too. `why` says why a value is as it is; this says who a change of a word would set off, who reads it and who calls it: ask before changing or renaming a word.

### 13.11 Typed words of links

The engine's own words are typed (§18): `LinkWords.status`, `own` and `disabled`, and its commands `press`, `tryOut`, `reset`, `stop`, `enabledSet`, `check`, `set`, `upsert`, `remove`, with their params and answers as records (`PressLink`, `LinkOutcome`, `LinkCheck`, ...). The engine defines them through these words, and clients call them so: `registry.command(LinkWords.press).call((link: id, args: null, wait: true), by: ...)`. Over a board or remote, their `.name`.

A host's links built in Dart take their steps and conditions from typed words: `word.step(params)` is a call step (`{call, params}`), `boolState.flip(key:)` a flip step (bool states only), `state.holds(value, key:)` a condition, `fact.trigger(where:, once:)` and `state.becomes(value, key:, holding:)` triggers. The JSON they give is the links' own; references such as `$trigger.…` are written as JSON.

### 13.12 Controls

A reaction someone can press is a control: a button on a desk, a phone, a deck. `Links.controls()` gives those there are now, in the order of the links: active, with a manual trigger (or a host's trigger that becomes one), whose `only` holds. Each has:
- **`look`:** the manual trigger's options, the host's words for how to draw it.
- **`lit`:** for a control that sets something. It is the condition in `look['lit']`, else the state its single flip step flips, else whether the state its single call sets already holds the call's value. It is null for a control that only does something.
- **`unavailable`:** why the first command it would call cannot run now.

The engine keeps them as the state `links.controls` too (`LinkWords.controls`: a list of `{id, name, look, lit, unavailable}`), written whenever they change. A client that sees only the registry (a phone over remote, through a mirror) draws its buttons from it.

`links.takeStats()` answers what the engine's work on ticks cost since the last call (ticks, their time in microseconds by bucket, the controls worked out again) and counts afresh: for a host to log.

`registry.pressLink(id, by:)` presses and waits for the run to end. It answers null when the run went through, else why not: the press was refused, the link did not run, or the run failed. Over remote, `client.command(LinkWords.press)` answers a `CallResult<LinkOutcome>` and `whyNotPressed` says the same.

## 15. Links the user keeps

The engine composes the links it runs from the host's **sources** (named sets, read-only to the user: `source(name, definitions)`) and the user's **own** links, in that order. An own link with the id of a source's link replaces it in its place; with `enabled: false` it turns it off. A source set with `on: false` is off: its links and the own links replacing them are composed off (a plugin turned off takes its links, as the user changed them, with it). `dropSource(name)` withdraws one; own links that replaced its links stay, as the user's. `originOf(id)` tells where a link came from (`LinkOrigin`: the source, null for an own one, and `edited` when an own one replaces the source's).

Own links live in a `LinksStore` the host gives: loaded at start and on `reloadOwn()` (the host changed them, an undo), saved on every change made through the engine's commands:

| Command | Does |
|---|---|
| `links.check { link }` | parses a link and names what of the catalog it lacks; nothing is applied |
| `links.set { links }` | replaces the own links; refused whole when one is wrong or an id is twice |
| `links.upsert { link }` | adds one, or replaces the one with its id in its place |
| `links.remove { id }` | removes an own link; a source's link is turned off by an own one instead |

State `links.own` holds the own links as kept; `links.status` how each link stands.

Own states' values are the host's to persist: `exportOwnStates()` gives them, `Links(ownStates:)` takes them back in a new engine, and `importOwnStates(values)` in one made before they were read (those active take them at once, the others when they come; a value its type refuses is left out).
