# Loop settings — parlance

Schema — `specs/config.md` in the skill. The places below are read by
`loop.py` and their format is exact: the `unattended:` line, `traits:`,
`local traits:`, the ```gate block, the `commit language:` and
`reply language:` lines, and the three «Round budget» lines.

## Mode

unattended: no

## Traits

What this project IS. Every items file under a pack directory declares the
traits it needs, and `loop.py brief` merges the ones this list covers; it then
names every item it held back, so nothing is lost in silence.

Names from the skill's registry (`references/traits.md`) go on the first line.
A property the registry has no name for goes on the second, together with an
items file that needs it in `.claude/loop/items/` — that is how a project
extends the vocabulary instead of bending an existing name to fit.

traits: dart, two-sided-protocol, byte-limits, long-lived-process, public-package
local traits:

Why these, by properties of the code:

- `dart` — pure Dart pub packages, workspace resolution, analyzer-gated.
- `two-sided-protocol` — a host serves guests over a connection
  (`Host.serve`, `Host.join`, `packages/parlance/lib/src/remote/`); the peer
  controls what arrives: feed items, ops, apply results, protocol features.
- `byte-limits` — `SessionLimits` charges a remote session against
  `stateBytes`, `words`, `guards`, `choices`, `calls`, `subscription`,
  `backlog` (`lib/src/remote/session.dart:1057`); `HostLimits.light` bounds
  what a host remembers.
- `long-lived-process` — the registry/host outlives any single call: sessions
  reconnect, ticks are retained and evicted (`keepAway`, trail limit 10),
  plugins define and remove words at runtime.
- `public-package` — `schema.dart` and `app.dart` are a frozen developer
  contract (`tool/frozen.dart` against the last release tag; «only add, never
  break»), and the compat machinery (`builtAgainst`, `WordMismatch`,
  `breaksSince`) exists precisely because exported types are promises.

Not declared, deliberately: `dart2js` (no JS target of the library packages in
the gate; the web surface is the Flutter app), `isolates` (no isolate code),
`persistent-storage` (the journal appends day files but there is no schema or
migration), `screens` (the only UI is the journal viewer app, outside the
loop's bar), `native-plugin` (no platform code), `several-replicas` (one
registry per process; replicas are the app's concern, not the library's).

Own damage classes — comma separated, optional, read by nobody; they are a
vocabulary for whoever writes a lens's `breaks:`.

damage classes: crash, hang, wrong result, broken delivery, broken ordering, lost causality, silent drop, unbounded growth, data loss, DoS, compatibility break, wedged stream

## Language

Two independent settings. Drop either line and it is English.
`commit language` is the round commit's subject and body; `reply language` is
the round report in chat.

commit language: English
reply language: English

## Toolchain

Dart via FVM only: `fvm dart` (never bare `dart`), `fvm flutter` for the app.
Pinned by `.fvmrc` (flutter 3.47.1). The root pubspec is a workspace —
`fvm dart pub get` once at the root resolves every package.

Tests run per package, with the package directory as cwd: `fvm dart test`
(the root has no test directory; `fvm dart test` at the root prints usage and
exits non-zero). Timed at setup: parlance 569 tests ~7 s, parlance_generator
60 ~6 s, parlance_journal 21 ~2 s, parlance_links 21 ~2 s, parlance_mcp 40
~11 s. `packages/parlance/dart_test.yaml` sets concurrency 4.

Launch traps:

- `rpc_dart`, `rpc_dart_socket`, `rpc_dart_generator` come from a LOCAL
  CHECKOUT via `dependency_overrides` (`../rpc_dart/...` relative to the
  root). If that sibling checkout is missing or moved, `dart pub get`,
  `analyze` and `test` all fail with resolution errors — that is an
  environment defect, not a code defect.
- Never edit `*.g.dart` by hand (see Standing owner requirements).
- `tool/frozen.dart` and `tool/surface_map.dart` run from the repo root with
  `fvm dart run tool/<name>.dart`.

## Gate

The exact sequence before a commit, one command per line. `fvm dart analyze`
runs at the repository root and analyzes the whole workspace (~5 s).
`fvm dart test` runs in the package the round changed — parlance first, then
any other package whose `lib/` the round touched; a round that touches only
`.claude/loop/` records or docs runs the parlance suite as the canary.

```gate
fvm dart analyze
fvm dart test
```

NOTE at setup (HEAD f68582b): the gate is red before the loop's first round —
`packages/parlance/test/remote/newer_language_test.dart:4` has an unused
import (warning, analyze exit 2) and `packages/parlance/test/registry/calls_test.dart:5`
an unnecessary import (info). Seeded as backlog lead B-2; a round that does
not fix it still owes the gate's commands and reports the known-red lines.

## Probes

Bench scripts and probe harnesses live inside the packages so imports resolve
through the workspace: `packages/parlance/benchmark/*.dart`
(`memory_bench.dart`, `registry_bench.dart`, `remote_bench.dart`,
`realtime_bench.dart`, `big_doc_bench.dart`) and the test suites
(`packages/*/test/`). `.claude/loop/` holds only records; nothing generated
goes there. `build/`, `.dart_tool/` and `.tmp/` are gitignored and excluded
from analysis — scratch output goes under `.tmp/`.

## After the commit

Commands for an unattended run after a successful round commit (push,
notification); empty means nothing. Covered by permissions.allow like the gate.

```after-commit
```

## Round budget

The first two are limits the round applies to itself — nothing counts them for
you. Past them with no valid number the verdict is INCONCLUSIVE, not CLEAN.
`round cap` is the one number the script enforces.

probes: 3
canaries: 2
round cap: 30

Optional: stop after this many rounds in a row with no `severity: S1`.

s1 drought: 5

## Siblings

Implementations of one contract, one line per member; a FIXED round that
changes one accounts for all of them in `## Siblings`. The view contract
(`IRegistryView`: synchronous reads, change notifications, calls as one
principal) has three implementations the where-test already runs as four
combinations; a fix to one member owes a witness on the others.

```siblings
view/local: packages/parlance/lib/src/view/view.dart, packages/parlance/lib/src/participant/local.dart
view/remote: packages/parlance/lib/src/remote/participant.dart, packages/parlance/lib/src/remote/mirror.dart
```

## Targets nobody runs

- `fvm dart run tool/frozen.dart` — checks `schema.dart`/`app.dart` against
  the last `v*` tag and builds that tag's `.g.dart` fixtures with the current
  library. CANNOT RUN YET: no `v*` tag exists (the first release tag is the
  point of comparison, план-api.md Е.27). Finds: frozen-surface drift,
  contract breaks invisible to tests.
- `fvm dart run tool/surface_map.dart` — rewrites `docs/карта-поверхности.md`
  (gitignored): which surface members no test reaches. ~15 s. At pass 10 it
  reported 0 members outside tests.
- `fvm dart run benchmark/<name>.dart` in `packages/parlance` — retention and
  throughput under load (memory, registry, remote, realtime, big_doc). Not
  wired into CI; the load/long-livedness area has never been measured by
  running (backlog B-1).
- `fvm flutter analyze` and `fvm flutter build web` in `apps/journal_viewer`
  — the only UI (web + macOS), outside the library gate.
- wasm/JS guests (design mentions guest wasm): no build target exists in this
  repository.

## Severity bar

Worth a round now, in this order:

- S1 — a defect reachable from OUTSIDE the process: wire input a guest
  controls, protocol/feed handling, delivery guarantees under reconnect,
  session-limit accounting, anything that silently drops or duplicates a
  peer's words. Also silent data loss in the journal.
- S2 — a leak of the frozen developer contract (`schema.dart`/`app.dart`):
  a promise (doc, type, behaviour) the code does not keep; a wrong result
  rendered through a public API.
- S3 — internal quality in the registry core, generator, links engine, MCP
  tools: wrong result reachable only from the library's own code, growth
  without a bound, dead paths.

## Out of scope

- The journal viewer app's UI behaviour and looks (`apps/journal_viewer`) —
  gate it with flutter tooling, not this loop.
- Examples (`examples/guests`) as teaching material — only their compiled
  correctness matters.
- Code generation style and the generator's output formatting — defects in
  the generator's INPUT contract are in scope; taste is not.
- Documentation prose audits as a class (a single divergence that carries a
  promise is an ordinary round; sweeping docs for style is not).
- Performance work without a correctness claim attached (benches exist for
  measurement, not for optimisation rounds).

## Standing owner requirements

What holds in every round:

- `fvm dart` / `fvm flutter` only — never bare `dart` or `flutter` (`.fvmrc`
  pins the SDK).
- Never edit generated files (`*.g.dart`, `*.freezed.dart`) by hand —
  regenerate with `fvm dart run build_runner build`.
- The frozen surface only grows: no rename, no removal, no new required
  parameter, no meaning change in `schema.dart`, `app.dart`, `IOwner`, the
  `IWord` family (`план-api.md` rules 20-22). A round that needs a break
  surfaces it as an owner decision, not a change.
- One commit per round, no AI attribution, no emoji, terse English subjects
  in the repo's existing style (`fix: ...`, `docs: ...`).
- Docs in `docs/` are Russian and are secondary sources (rule one): the code
  decides. `docs/протечки.md` is the prior leak audit — its «closed» marks
  are leads-checked, not loop-checked, except where copied into `checked/`.

## Known flakes

None known. The remote tests run over real loopback sockets; if one starts
failing intermittently, name it here rather than re-running until green.
