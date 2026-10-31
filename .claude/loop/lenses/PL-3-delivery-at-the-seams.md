---
refines: —
paths: [packages/parlance/lib/src/remote/session_feed.dart, packages/parlance/lib/src/remote/participant.dart, packages/parlance/lib/src/remote/mirror.dart]
applies: delivery promises per message kind (state as current value, fact at most once, call once per id; a long gap says factsLost); a session lives across frames, obsolescence and reconnects; two-sided-protocol
breaks: broken delivery, wedged stream
applied: []
status: derived
rank: 3
---

# PL-3 — delivery guarantees at the seams: resume, late end, away facts

## Shape

The promises are per kind, but the seams are shared: a feed that resumes from
`since`, a handler that ends late, facts held for an away guest (`keepAway`,
default 1000, `remote/participant.dart:138`), a snapshot that must not
overlap live ticks. A defect lives in the combination — the where-matrix and
`feed_gaps` tests cover many pairs, so the holes are in the pairs they do not
hold.

## Detector

- Seq bookkeeping: `_held`, `_valuesDropped`, the frame checks
  (`i.$1.kind == 'tick'`, `session_feed.dart:90-100`) — for each, the test
  that drives a gap, and the gap it does not drive.
- The promise table (`термины.md` §14.1) as a matrix: {state, fact, call} x
  {clean run, resume from since, resume past retention, late handler end,
  cancel before start, cancel after start, session closed by host, transport
  dropped mid-tick}; each cell names its test or is a candidate.
- `Host.join` reconnection (`_synced`, `reach`) — does the resend after
  reconnect repeat anything the peer already applied?

## Ask

For each empty cell: run it and count what the receiving participant
observes — delivered twice, delivered zero times, or blocked forever. A cell
whose test exists but only on one side of the wire (local guest, not remote)
is empty until run both ways.

## Evidence

—
