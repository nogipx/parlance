---
round: 1
verdict: FIXED
packages: [parlance]
lens: PL-1
bench: none — the probe is the workspace analyzer itself (`fvm dart analyze`); exit code and issue count are the number, no bench file is possible for a lint
commit: yes
severity: S0 — "not a product defect: the loop's tooling, gates, tests"
release: none
---

# Round 1 — gate red imports

## Target

Backlog lead B-2: the two import lints that keep `fvm dart analyze` red at
HEAD (exit 2), confirmed by running it this session:

- `packages/parlance/test/remote/newer_language_test.dart:4` — unused import
  `package:parlance/src/remote/client.dart` (warning)
- `packages/parlance/test/registry/calls_test.dart:5` — unnecessary import
  `package:parlance/schema.dart` (all used elements also come from
  `package:parlance/tools.dart`) (info)

Why this and not B-1 (load/retention unmeasured, PL-4): B-2 wins on
severity-first grounds even though the lint itself is below the product bar.
A red gate corrupts the evidence of every later round — a green gate is the
loop's core control, and until it is green each round must eyeball its gate
output against two known lines, which erodes exactly the CONFIRMED-evidence
rule the loop stands on. B-1 is a measurement round with no defect claim
(yielding at best a bench or a negative), it spends one of the round's 3
bench rebuilds, and it is untouched by the red gate. Fix order: restore the
instrument first, then measure with it. B-2 is cheap, deterministic and its
verification is the gate itself.

Files and symbols: only the two import directives above; no code symbols.
No bench exists (`find --kind probe` reports 0 valid benches) and none is
needed — the probe is the analyzer itself. No sibling group is touched (both
files are tests, not members of «view»). Records weighed: B-1 (dismissed for
this round — above), B-2 (taken); lenses PL-1..PL-5 all `derived`, none
covers test files, so no lens sweep was due first; negatives C-1/C-2 do not
cover these paths.

`lens: PL-1` is the nearest area lens (its paths own `lib/src/remote/**`,
the code `newer_language_test.dart` exercises), not the source of this
target — the target came from the backlog, and no lens's detector applies to
test hygiene. Recorded here so the attribution is not mistaken for a PL-1
sweep.

## Hypothesis

Removing the two dead imports makes `fvm dart analyze` exit 0 with no other
output change, and no test in packages/parlance depends on either import for
its symbols (the imports contribute nothing — if removing them breaks a
compile, the hypothesis fails).

## Before

```text
fvm dart analyze (repo root), exit 2:
warning - packages/parlance/test/remote/newer_language_test.dart:4:8 - Unused import: 'package:parlance/src/remote/client.dart' - unused_import
info    - packages/parlance/test/registry/calls_test.dart:5:8 - The import of 'package:parlance/schema.dart' is unnecessary because all of the used elements are also provided by the import of 'package:parlance/tools.dart' - unnecessary_import
2 issues found
```

Probe: `fvm dart analyze` at the repository root — the workspace analyzer is
its own instrument; its exit code and issue count are the number.

## Mechanism

Two dead import directives in test files. `client.dart` is imported in
`newer_language_test.dart` but no element of it is referenced anywhere in the
file (unused import). `calls_test.dart` imports `schema.dart` with
`show failCall, HandlerFailed`, and both symbols are used — but both are
re-exported through `tools.dart`, which the file also imports, so the
directive is redundant (unnecessary import). Nothing else differs between
the two files' compile-time view with and without the directives.

## After

```text
fvm dart analyze (repo root), exit 0:
No issues found!
```

Same probe, same tree otherwise. The 569-test parlance suite also passes on
the removed imports (see Gate).

## Canary

Fix switched off in place: both import directives re-added with `Edit`.
Witness `fvm dart analyze` failed with the real messages "warning -
packages/parlance/test/remote/newer_language_test.dart:4:8 - Unused import:
'package:parlance/src/remote/client.dart' ... - unused_import" and "info -
packages/parlance/test/registry/calls_test.dart:5:8 - The import of
'package:parlance/schema.dart' is unnecessary because all of the used
elements are also provided by the import of 'package:parlance/tools.dart'
... - unnecessary_import" (exit 2, 2 issues found). Imports removed again:
analyze green. Witness: the analyzer diagnostics; guard: the removed imports
staying removed.

## Gate

- `fvm dart analyze` at the repository root: "No issues found!", exit 0.
- `fvm dart test` in packages/parlance: 569 tests passed.

## Siblings

— no sibling group touched: both changed files are tests, not members of
«view».

## Not fixed

Nothing in this target. B-1 (load/retention unmeasured, PL-4) was
deliberately not taken this round: a measurement round with no defect claim,
untouched by the red gate; it remains the next round's candidate.

## Links

- B-2 — closed (round 1).
- PL-1 — `applied:` gains round 1 via sync; status stays `derived`: the lens
  did not produce this target (no detector covers test hygiene), the
  attribution only prevents mistaking it for a PL-1 sweep.
- C-2 — its claim (test suites green at HEAD) is re-confirmed for
  packages/parlance by this round's gate.
