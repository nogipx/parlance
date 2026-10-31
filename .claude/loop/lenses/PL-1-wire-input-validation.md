---
refines: —
paths: [packages/parlance/lib/src/remote/**]
applies: a guest connects over a connection and controls every byte the host parses; two-sided-protocol
breaks: crash, wrong result
applied: [1]
status: derived
rank: 1
---

# PL-1 — wire input a guest controls, parsed before it is checked

## Shape

Every value the host reads off the connection arrives as JSON built by
someone else: `WireFeedItem(kind, item)` (seven kinds: `catalog`, `snapshot`,
`tick`, `values`, `kind`, `unavailable`, `ended`), op results to an `apply`,
protocol `describe` features, word definitions from a guest. Parsing uses bare
casts (`WireFeedItem(m['kind'] as String, _obj(m['item']))`,
`contract.dart:101`).

## Detector

Enumerate the parse surface, then attack it:

- `grep -n " as " packages/parlance/lib/src/remote/contract.dart
  packages/parlance/lib/src/remote/session_feed.dart
  packages/parlance/lib/src/remote/participant.dart` — every cast on wire
  data is a candidate throw.
- For each of the seven feed kinds: its handler in `session_feed.dart` and
  `remote/session.dart` (`_carry`, `_held`, the `i.$1.kind == 'tick'` frame
  checks), and what a malformed `item` does there.
- `Host.serve`/`join` negotiation: unknown or re-defined `Feature` names in
  `describe` (`contract.dart`), `requires` handling, `ProtocolMismatch`.
- Battery: a hostile fake guest sending each kind with missing/extra/wrongly
  typed fields, an unknown kind, and a kind that lies about its content.

## Ask

Can a guest's malformed or hostile message throw inside the host's registry
loop, be silently treated as a valid op, or make the host charge limits
against the wrong session? The answer comes from running the battery, not
from reading: the pass-9 audit (Н2, Н3) fixed two instances of exactly this
class and its own doc says reading is not a run.

## Evidence

—
