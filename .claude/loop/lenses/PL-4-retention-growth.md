---
refines: U-20
paths: [packages/parlance/lib/src/registry/**, packages/parlance/lib/src/remote/**, packages/parlance/benchmark/**]
applies: a host process outlives every call; plugins define and remove words at runtime; ticks are retained and evicted; long-lived-process
breaks: unbounded growth, performance regression
applied: []
status: derived
rank: 4
---

# PL-4 — retention that must return to baseline when the load stops

## Shape

A long-lived registry accumulates: ticks and their eviction
(`_forgottenChanges`), recent facts per away guest (`keepAway`), call
records, conversation memory, compat judgements (`_judged`, an Expando),
usage counters (`registry/uses.dart`), subscription state per session. Each
structure either has a measured bound and returns to it when load stops, or
grows without one.

## Detector

- `grep -rn "keepAway\|_forgotten\|_recent\|trail" packages/parlance/lib/src`
  — each hit is a structure; write down its bound and its eviction trigger.
- `packages/parlance/benchmark/memory_bench.dart` — run it; if it has no
  baseline-and-ablation shape, build the bench first (control: disable the
  eviction under test and watch the rise the production code claims not to
  have).
- The define-remove cycle: a plugin defining and removing words K times;
  memory after N cycles vs after 1, with the registry otherwise idle.

## Ask

After each load shape stops, does the structure return to its pre-load size —
measured, in bytes or counts, against the ablation? Reading the eviction
code is not the answer: the pass-10 audit explicitly left this area
«только чтением, не прогоном» (backlog B-1).

## Evidence

—
