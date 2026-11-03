---
refines: U-08
paths: [packages/parlance/lib/src/remote/session.dart, packages/parlance/lib/src/remote/participant.dart, packages/parlance/lib/src/host.dart]
applies: SessionLimits charges a remote session against stateBytes, words, guards, choices, calls, subscription, backlog (defaults 1<<20, 256, 16, 1000, 16, 4096, 256); byte-limits, two-sided-protocol
breaks: DoS, unbounded growth
applied: [3]
status: derived
rank: 2
---

# PL-2 — a session limit charged on the happy path and wrong on another

## Shape

A limit is checked where the ordinary flow reaches it — and not where the
error path, the retry, the removal-and-readd cycle, or the bulk op reaches
the same resource. The charge and the release live in different places, so a
guest that knows the gap holds more than its limit, or grows the host without
bound.

## Detector

One walk per `SessionLimits` field, found by `grep -n "limits\." packages/parlance/lib/src/remote/session.dart`:

- charge site (e.g. `limits.subscription` at `session.dart:365`,
  `limits.stateBytes` at `:814`) — is the refusal before any partial
  application, or after?
- release site — is the count returned when a word is undefined, a key
  removed, a guard dropped, a session closed mid-backlog?
- second door — the same resource reached differently: `HostLimits` on the
  host side, `keepAway` facts held for an away guest, `_carry` resuming a
  subscription after a gap.

Then the matrix: each limit x {exceed directly, exceed by error path, exceed
by rapid remove/re-add, exceed while a limit sits at `unbounded`}.

## Ask

For each limit: name one traffic shape that gets more of the resource past
the charge than the limit allows — or measure that none exists. A limit that
was never probed past its refusal is assumed unenforced on that path.

## Evidence

—
