---
round: 2
verdict: FIXED
packages: [parlance]
lens: PL-1
bench: P-1 — new
commit: yes
severity: S2 — "a status or error type a caller branches on"
release: changelog
---

# Round 2 — wire decode guest frames

## Target

Lens PL-1, host-side decode surface: the RPC endpoint `fromJson` factories in
`packages/parlance/lib/src/remote/contract.dart` parse frames a guest builds,
and they use bare casts on guest-controlled fields:

- `WireCallRequest.fromJson` (`contract.dart:123-129`): `m['id'] as String`,
  `m['command'] as String`
- `WireSubscribe.fromJson` (`contract.dart:80-83`):
  `(m['states'] as List?)?.cast<String>()` — a non-String entry throws
- `WireFeedItem.fromJson` (`contract.dart:100-101`):
  `m['kind'] as String`
- `WireWhyRequest`/`WireRecentRequest`/`WireDefine`/`WireName` and the rest of
  the contract file (count the class: `grep -n " as " contract.dart`)

These factories run inside the rpc_dart layer BEFORE the session's handlers
(`onInvoke`/`onSubscribe`/`onFeed` in `packages/parlance/lib/src/remote/
session.dart`) see the request, so the containment that `onApply` has (its
per-op try/catch at `session.dart:606-618`) does not cover them. Whether a
badly-typed frame becomes a clean protocol refusal or an uncaught throw in
the host's connection loop is a question only running answers — exactly what
the PL-1 lens's Ask demands ("the answer comes from running the battery, not
from reading"). Severity-first: this is S1 in the config's bar ("wire input a
guest controls"), reachable from outside the process by any guest, one
mechanism (decode-before-dispatch), countable as a class across one file.

Why this and not the alternatives, weighed in `loop.py find`:

- B-1 (load/retention unmeasured, PL-4): dismissed — the owner asked for bugs
  and API shortcomings; B-1 is a measurement-only bench build with no defect
  claim, and it would spend one of the round's 3 bench rebuilds.
- PL-2 (session-limit accounting, rank #2, never applied): read first. All
  seven charge sites exist and their release sites are present and balanced on
  current code — `words` define/undefine (`session.dart:745-794`), `stateBytes`
  per-key weight released on remove and undefine (`:796-839`), `choices`
  set/unkind (`:884-923`, op at `:672-677`), `guards` guard/unguard/end
  (`:927-951`, `:680-681`, `:1030`), `calls` charged after the check and
  released in `finally` (`:488-515`), `subscription` refused before mutation
  (`:358-380`), `backlog` enforced by `_Feed.send`/`_drop`
  (`session_feed.dart:110-114`). No unenforced pair surfaced by reading, so a
  PL-2 round today would be a matrix sweep most likely to yield negatives;
  deferred, and the SessionLimits class docs (`session.dart:1052-1107`) make a
  good invariant candidate if the drought continues.
- PL-3/PL-5: lower rank; PL-5's ~60 catch sites are a success-path sweep, not
  a single mechanism.
- Negatives C-1/C-2 do not cover this surface (C-2 is a green-run snapshot).

Under-tested, not unswept: `packages/parlance/test/remote/
malformed_host_test.dart` covers the OPPOSITE direction — a malformed host
attacking the client/mirror — and `session_test.dart:102-103` covers per-op
`invalidArgument` inside `onApply`. Nothing sends a badly-typed frame INTO a
real host session and watches what the decode layer does. Round 1's record
carries `lens: PL-1` but explicitly says it was a gate fix, not a PL-1 sweep —
this round is the first actual PL-1 application.

Files/symbols: `packages/parlance/lib/src/remote/contract.dart` (all endpoint
`fromJson` factories), `packages/parlance/lib/src/remote/session.dart`
(`onInvoke`, `onSubscribe`, `onFeed` as the dispatch behind the decode),
`packages/parlance/test/remote/malformed_host_test.dart` (harness pattern to
reuse: `RpcChannelTransport.memoryPair` + a hand-rolled contract peer; the
hostile peer here is the GUEST side). Bench: none exists (`find --kind probe`
reports 0 valid); the round builds one hostile-guest bench and registers it
(probes: 3, one spent). No sibling group: contract.dart/session.dart are not
members of «view»; if the fix touches participant.dart or mirror.dart, the
«view/remote» sibling lines are owed.

Execute note: the first battery measured the WRONG mechanism — over a
zero-copy-capable memory pair an `auto`-mode caller sends OBJECTS, not bytes,
so the host failed at rpc_dart's `directPayload as TRequest` and never ran
its request codec. The bench pins `RpcDataTransferMode.codec` on the hostile
caller; the discarded measurement is the lesson L-1's price.

## Hypothesis

A guest that sends a syntactically valid JSON-RPC frame whose parlance fields
are wrongly typed (call request with numeric `id`, subscribe with a non-String
entry in `states`, feed item with non-String `kind`) makes the host's decode
throw a `TypeError`/`CastError` that escapes the declared refusal surface —
either it kills the host-side connection handling for that session (the guest
disconnects or the endpoint errors) or it surfaces as an internal/malformed
error with no clean refusal — instead of the host refusing the frame the way
it refuses a semantically bad op. Confirming evidence: a battery of such
frames over a memory transport against a real served session, where the
observable is the connection liveness and the error the guest receives; a
control of well-formed frames shows the bench sees a healthy session, and
ablation (a frame that is refused cleanly by an existing path, e.g. a bad op
inside `onApply`) shows the bench can tell a clean refusal from an escape.

## Before

```text
Corrected bench (hostile caller pinned to codec mode), fix switched off in
place (canary state — _badType reproduces the pre-fix bare cast):

10/10 wrongly-typed frames -> status=13 internal: Internal server error
  (call id, why state, recent count, subscribe states, set state,
   emit fact, undefine name, cancel name, define descriptor, feed since)
session: alive after every frame; describe still answered after every frame
control: well-formed describe answered; well-formed call frame answered
ablation: apply with a semantically bad op -> {results: [{error: notFound,
  message: no state no.such}]}
```

The guest-side runtime type is a plain `RpcStatusException` — a redacted
`INTERNAL` (13) with `kInternalErrorWireMessage`: rpc_dart's request-decode
catch answers any exception that is not its internal `RpcPeerFaultException`
this way, and a `TypeError` is not one.

Probe: `packages/parlance/test/remote/hostile_guest_decode_test.dart`

## Mechanism

The endpoint factories read guest-controlled fields with bare `as` casts; a
wrongly-typed field throws a `TypeError` inside rpc_dart's request-decode
catch (`base_processor_responder.dart`), which passes through only
`RpcPeerFaultException` and answers everything else as a redacted `INTERNAL` —
the verdict reserved for a host bug, with the message hidden. The host's own
refusal vocabulary for guest mistakes is `INVALID_ARGUMENT`
(`session.dart:701,711,722,835,867`), and the client branches on the
difference: `answeredBySession` (`client.dart:14-21,237-248`) maps the
`invalidArgument` family to `CallFailed('invalidArgument: ...')` and everything
else, `INTERNAL` included, to `CallLost(callId)` — "the answer was lost", the
retry path, with no diagnostic. So a guest's own bad frame is reported as the
host having failed and lost its call, instead of a refusal naming the field.

The fix classifies at the read: `contract.dart`'s factories now read every
guest field through typed helpers that throw
`RpcPeerFaultException(RpcStatus.invalidArgument, '"field" is not of the
expected type: ...')`. rpc_dart's catch passes that type through untouched,
so the guest is told `INVALID_ARGUMENT` with the diagnostic; the host logs it
as a peer fault, not an incident. The type is the decode catch's designed
extension point but is missing from rpc_dart's public barrel ("every name is
listed on purpose"), so `contract.dart` imports it from
`package:rpc_dart/src/core/errors.dart` under `// ignore:
implementation_imports`; lead B-3 asks the owner to export it upstream. The
whole class in the file is fixed (16 factories; `WireDescription`/`WireJson`
are pass-through by shape, `WireTaken`/`WireServed` already check before
casting).

## After

```text
Same probe, same bench, fix on:

10/10 wrongly-typed frames -> status=3 invalidArgument, message names the
  field, e.g. "id" is not of the expected type: 1
host log: "Sending status to client: 3 - ... [peer fault]" (not an incident)
session: alive after every frame; describe still answered after every frame
control: well-formed describe answered; well-formed call frame answered
ablation: unchanged — {results: [{error: notFound, ...}]}
```

## Canary

Fix switched off in place: `_badType` was edited to the pre-fix mechanism
(`final String _ = v as String;` — the bare cast's TypeError). The witness
`packages/parlance/test/remote/hostile_guest_decode_test.dart` failed with a
real message, not a timeout:

```text
Expected: RpcStatus:<RpcStatus.invalidArgument>
  Actual: RpcStatus:<RpcStatus.internal>
call, id a number
```

All nine other cases failed the same way (13 where 3 was expected). Restored
with `Edit`: witness green. One mechanism, one canary; the witness is the
status+message the guest receives, the guard is the paired control (a
well-formed call frame must still be answered, and is).

## Gate

- `fvm dart analyze` at the repository root: "No issues found!", exit 0
  (the src import's `implementation_imports` lint is silenced by an
  `// ignore:` with the reason in the comment).
- `fvm dart test` in packages/parlance: 570 tests passed (569 + the new
  witness).

## Siblings

— no sibling group touched: the changed file (`contract.dart`) is not a
member of «view/local» or «view/remote», and the fix reaches no participant/
mirror code.

## Not fixed

The zero-copy direction of the same class: over a zero-copy-capable
transport, an in-process guest's OBJECT is delivered via rpc_dart's
`directPayload as TRequest` (`base_processor_responder.dart`), which still
renders `INTERNAL` for a wrongly-typed object and lives entirely inside
rpc_dart — parlance never sees the object, so there is nothing to classify in
this repo. Both this and the barrel export of `RpcPeerFaultException` are one
lead: B-3 (owner decision, rpc_dart side).

## Links

- P-1 — new bench, valid, promoted to `packages/parlance/test/remote/
  hostile_guest_decode_test.dart`.
- L-1 — new lesson: over a zero-copy-capable in-memory pair, pin the hostile
  caller to `RpcDataTransferMode.codec`, or the bench measures the
  direct-cast path, not the decode path.
- B-3 — new lead: rpc_dart to export `RpcPeerFaultException` from the public
  barrel (drops the src import) and to classify the zero-copy direct-cast
  refusal.
- PL-1 — `applied:` gains round 2 via sync; status `confirmed (round 2)`,
  first real application of the lens.
