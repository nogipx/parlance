---
round: 3
verdict: FIXED
packages: [parlance]
lens: PL-2
bench: P-2 — new
commit: yes
severity: S1 — "memory or CPU a peer or ordinary use can grow without bound"
release: breaking
---

# Round 3 — session byte charge gap

## Target

Lens PL-2 (rank 2, never applied), the byte dimension of its Ask: "name one
traffic shape that gets more of the resource past the charge than the limit
allows — or measure that none exists." The resource is host memory
attributable to a served session; the only per-session byte charge is
`stateBytes`, and it is wired solely to state values in `_write`. Every other
guest-supplied byte stream reaches retained host memory with no per-session
byte check:

- `_define` (`session.dart:750-781`): the word limit (`words`, default 256,
  :753) counts entries; the descriptor's bytes (label, schema `prints`,
  keys) are retained in the registry catalog uncharged.
- `_choicesOf` (`session.dart:889-928`): the choices limit (default 1000,
  :894-905) counts entities; each entity map (`id`, `label`, `meta`) is
  retained in `_choices[name].list` and served in every catalog describe,
  meta bytes uncharged and with no global byte bound at all.
- `_say` (`session.dart:846-876`): fact payloads carry guest bytes; retention
  is bounded only by GLOBAL `HostLimits` (`registry/registry.dart:36-83` —
  `recentPerFact` 100 per name, `retainBytes` 4<<20 per history), so one
  session can fill the shared budget other principals write against. No
  session limit fires.

Severity-first: the config's S1 list names "session-limit accounting" and
"grows the host without bound"; PL-2's `breaks:` are DoS and unbounded
growth; the shape is reachable from outside by any served guest, one
mechanism (the byte charge attached to exactly one of the retained
structures), countable as a class. Drought is 2/5 — this is the strongest
S1-shaped claim available.

Records weighed, on current code (read this session, not from memory):

- Round 2's dismissal of PL-2 (`rounds/2`): it verified the seven default
  charge/release PAIRS balanced by reading and deferred the matrix. This
  round takes the one cell reading cannot settle — per-entry bytes versus
  the only byte limit — so there is no contradiction: the pairs are balanced
  AND the byte charge may still have a hole. Re-verified on current code:
  subscription (`session.dart:370`, refused before mutation), calls
  (:493-504, checked before `_calling++`, released in `finally` :517-519),
  words (:753 before `_define`, released `_undefine` :783-799), stateBytes
  (:819-826 before the write, released on remove :834-838 and undefine
  :795-797), choices (:894-905 before mutation, released at 'unkind'
  :677-682), guards (:935-939 before add, released 'unguard' :685-686 and
  `_end` :1035), backlog (`session_feed.dart:110-114`). All balanced.
- PL-3 (rank 3): the delivery matrix cells are largely covered by on-disk
  suites (`feed_gaps`, `feed_backlog`, `subscription_bound`, `takeover`,
  `connection_gone`, `ended`, `kinds_feed`, `settle`, `flush`); no crisp
  empty cell surfaced from reading `session_feed.dart`/`session.dart` within
  the select budget. Deferred.
- PL-4 / B-1 (rank 4 / lead 1): measurement-only — needs a load-run bench
  build, spends one of the round's probe rebuilds, and yields at best a
  negative or a bench, not an S1. Deferred while an S1-shaped claim stands.
- PL-5 (rank 5): a ~60-catch success-path sweep, not one mechanism; round 2
  weighed this already.
- C-1/C-2: do not cover session-limit byte charging. B-3: owner decision,
  different repository.

Files/symbols: `packages/parlance/lib/src/remote/session.dart` (`_write`
:801-844 — the only byte charge; note the charge is `jsonWeight(value) +
(key?.length ?? 0)` at :818, booked at :833-838), `_define` :750-781,
`_choicesOf` :889-928, `_say` :846-876; `packages/parlance/lib/src/registry/
registry.dart` (`HostLimits` :36-83, global retention bounds, call-record
weighing :799-800); `packages/parlance/lib/src/registry/json.dart`
(`jsonWeight` :80-102, the weighing function). Breadth (count the class
first, executor): `grep -n "_bytesHeld\|_bytes\[" session.dart` — only
`_write` books bytes; then enumerate every guest-fed retained structure
(descriptors, choice lists, fact payloads, call params/results) and name
which bound, if any, each one answers to.

Bench: none valid on these paths — `find --path session.dart --kind probe`
reports none; P-1 covers `contract.dart` (status codes, not bytes). Reuse
P-1's harness PATTERN only: a real served `RemoteSession` on one end of an
`RpcChannelTransport.memoryPair`, hand-rolled peer on the other, and pin the
peer to `RpcDataTransferMode.codec` (L-1). The measure is new (host-side
retained bytes vs. limits satisfied), so this spends a second probe rebuild
(probes: 3, one spent on P-1). No sibling group: the charge sites live in
`session.dart`, not a member of «view» — but if the fix reaches
`remote/participant.dart` or `remote/mirror.dart` («view/remote»), the
sibling lines are owed.

## Hypothesis

A guest served under the DEFAULT `SessionLimits` retains host-side bytes that
no session limit charges: `define` descriptors, `kind` entity maps (incl.
`meta`), and `emit` payloads all reach retained registry/session memory
while `words` (256) and `choices` (1000) stay satisfied and `stateBytes`
(1 MiB) never fires, being wired only to state values in `_write`. One
concrete shape suffices to confirm: one session defining its allowed words
with fat schema prints, or setting choices with fat `meta`, or emitting fat
payloads, holds retained bytes many times the 1 MiB `stateBytes` default
with zero refusals. Confirming evidence: a served session driven over a
memory transport performing those ops within every default COUNT limit,
while the probe sums the host-side retained bytes (the registry's own
`jsonWeight` over what it kept, or a heap figure) — growth without a
per-session byte refusal confirms; a control of plain `set` writes of the
same bytes trips `stateBytes` (`resourceExhausted`), showing the bench sees
a refusal when a charge exists. If every retention path turns out bounded by
a per-session byte check the reading missed, the verdict is CLEAN and the
measured bounds are the round's product.

## Before

```
held=19191548 vs stateBytes=1048576; errors=[resourceExhausted: the session holds at most 1048576 bytes of values: g.s0 would make it 2097168]
```

Probe: `packages/parlance/test/remote/session_byte_charge_test.dart` — a
served guest under DEFAULT limits fed 255 state descriptors with 64 KiB
`meta` each, 1000 kind entities of ~1.1 KiB, and 100 fact payloads of
~12 KiB: all retained, zero per-session byte refusals — 19,191,548 bytes
(18.3x the default bound). Descriptors and kinds answer to count limits
only (words 256, choices 1000): no byte bound at all. Payloads answer to
global `HostLimits` only (100 recent / 4 MiB per fact): one session with
its 256 facts could park ~1 GiB against the shared budget. The single error
is the control: a plain `set` of ~2 MiB, the one charged structure,
refused by `stateBytes` — the bench sees a refusal where a charge exists.

## Mechanism

`stateBytes` was wired to exactly one of the retained structures: state
values in `_write` (`_bytes`/`_bytesHeld`). `_define` consulted only the
word count, `_choicesOf` only the entity count, `_say` no byte check at
all — every other guest-fed byte stream reached retained host memory
uncharged.

## After

```
default limits: 31 fat defines pass, the 32nd refused —
the session holds at most 1048576 bytes: the word a.d31 would make it 1056679
custom limit 8447: the second 1549-byte payload refused —
the session holds at most 8447 bytes: a payload of c.f would make it 9868
```

Same probe file, now the witness: one ledger (`_bytesHeld`) sums state
values, word descriptors (`_wordBytes`, released at `undefine`), kind
entities (`_kindBytes`, delta-charged on re-kind, released at `unkind`) and
emitted payloads (counted for the session's life); each site refuses
`resourceExhausted` past `limits.stateBytes`, so under default limits the
byte bound fires long before the 256-word count. The same shapes pass under
SessionLimits.unbounded, small content passes under the default limits, and
after `undefine`/`unkind` the same sizes define and kind again.

## Canary

Bound half: with `_chargeBytes` switched off in place (`if (1 > 0) return;`)
the witness failed with real messages — 'the session defines 256 words, as
many as it may' (the count limit, not bytes) and the second payload
'returned a Future that emitted <WireTaken>' instead of throwing.
Release half: with the `_wordBytes` release in `_undefine` removed, the
witness failed with 'RpcStatusException(8): the session holds at most 8447
bytes: the word c.w2 would make it 10058'. Both restored; witness green.

## Gate

`fvm dart analyze` at the repository root — no issues found. `fvm dart
test` in packages/parlance — 571 passed, 0 failed. The only collision was
session_limits_test's 200-byte stateBytes budget, which the word
descriptor (~199 bytes) now shares; raised to 400 with a comment — the test
still measures that a keyed state stops at its bytes and that removing one
makes room.

## Siblings

— session.dart is not a member of either sibling group («view/local»,
«view/remote»); the charge lives only in RemoteSession and the view members
are untouched.

## Not fixed

- Invoke params/results: a guest's call params are retained in the
  registry's `_recentCalls` (global bounds: retainTicks 1000, retainBytes
  4 MiB per history; params validated against the host-declared RecordType,
  so byte-unbounded but shape-constrained). No per-session charge; reachable
  only when a host defines a callable command and grants the guest rights.
  Charging typed-but-unbounded params is the same ledger mechanism, left for
  a round that can also carry its witness.
- Guard ids (guards 16) and subscription names (subscription 4096):
  count-bounded identifiers with no byte bound anywhere; bounding their
  bytes is a different mechanism (identifier-length validation).
- Registry `_callWeight` (registry.dart:798) weighs params+result but not
  the guest-controlled call id retained as the map key of `_recentCalls` —
  a gap in the GLOBAL byte accounting, a different mechanism than the
  session charge fixed here.

## Links

PL-2 — confirmed (round 3); this record is its evidence. P-2 — new bench,
promoted to packages/parlance/test/remote/session_byte_charge_test.dart.
L-1 — applied (caller pinned to codec mode). Round 2's balanced-pairs
reading re-verified on current code (see Target). No leads opened or
closed; B-1/PL-4 remains the place a load-run measurement would go.
