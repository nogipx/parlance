---
refines: U-06
paths: [packages/parlance/lib/src/**, packages/parlance_links/lib/src/**, packages/parlance_journal/lib/src/**, packages/parlance_mcp/lib/src/**]
applies: every path that reports success afterwards — a refused call, a skipped journal line, a link that did not start — must have a channel that says the work did not happen
breaks: silent drop, wrong result
applied: []
status: derived
rank: 5
---

# PL-5 — a catch that swallows the failure the caller will never hear of

## Shape

A `catch` (or `onError`, or a future ignored) on a path whose outcome is
later reported as success: the call is `done`, the load completed, the tick
committed — but a piece of it failed and only the log saw it. Precedents paid
for in this codebase: Н1 (`Links.load` swallowed unreadable states and
started links on stale data, `parlance_links/lib/src/engine.dart:929-933`)
and J1 (the journal writer swallowed write errors until 2026-10-31).

## Detector

Enumerate every catch, then classify by what the surrounding path promises:

- `grep -rn "catch\|onError\|ignore()" packages/parlance/lib/src packages/parlance_links/lib/src packages/parlance_journal/lib/src packages/parlance_mcp/lib/src`
  — ~60 sites at setup (registry 16, remote 34, links 5, journal 7).
- For each site: what does the enclosing operation report when the catch
  fires? If the answer is «success, unchanged», what channel carries the
  failure — `errors` stream, `dart:developer`, the result value itself?
- Prioritise: catches in the frozen surface (`app.dart`/`schema.dart` paths)
  and in remote/ (a peer cannot see a local log).

## Ask

For each catch on a success-reporting path: either name the channel that
tells the caller, with the test that silences it when the failure is
programmer error (U-18), or measure that the swallowed failure changes an
observable outcome.

## Evidence

—
