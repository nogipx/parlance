---
status: open
round: 2
commit: 9e3639a3cb55ab22aa9335f91966b18a65e61f3d
paths: [../rpc_dart/packages/core/rpc_dart/lib/rpc_dart.dart, ../rpc_dart/packages/core/rpc_dart/lib/src/core/errors.dart, ../rpc_dart/packages/core/rpc_dart/lib/src/rpc/streams/base_processor_responder.dart]
probe: P-1
reason: owner decision — the fix lives in a different repository (rpc_dart); parlance already works around the first half
rank: 3
---

# B-3 — rpc_dart: export RpcPeerFaultException; classify the zero-copy direct-cast refusal

Measured in round 2 (P-1, `.claude/loop/rounds/2-wire-decode-guest-frames.md`):

1. rpc_dart's request-decode catch (`base_processor_responder.dart`) passes
   through ONLY `RpcPeerFaultException`, answering every other exception —
   including the public `RpcMetadataViolationException`, verified by running —
   as a redacted `INTERNAL`. The type is the designed extension point for "a
   payload the request codec could not decode" but is missing from the public
   barrel (`rpc_dart.dart` lists every exported name on purpose). parlance's
   `contract.dart` now imports it from `package:rpc_dart/src/core/errors.dart`
   under `// ignore: implementation_imports`; exporting it upstream drops the
   src import and the ignore.

2. The zero-copy direction of the same defect class: over a zero-copy-capable
   transport, `directPayload as TRequest` (`_processDirectMessage`) still
   renders `INTERNAL` for a wrongly-typed object an in-process guest sends.
   parlance never sees the object, so there is nothing to classify in this
   repo; the cast and its catch are rpc_dart's.

Owner decision: both halves are one-line-ish rpc_dart changes, but they are in
the sibling repository and cannot ride a parlance commit.

## Owner decision

—
