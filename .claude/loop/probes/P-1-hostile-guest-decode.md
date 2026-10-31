---
file: packages/parlance/test/remote/hostile_guest_decode_test.dart
round: 2 — the validating round
commit: 9e3639a3cb55ab22aa9335f91966b18a65e61f3d
paths: [packages/parlance/lib/src/remote/contract.dart]
status: valid
promoted: packages/parlance/test/remote/hostile_guest_decode_test.dart
---

# P-1 — what a host answers a guest's wrongly-typed frame

A real `RemoteSession` served on one end of an `RpcChannelTransport.memoryPair`;
the hostile guest on the other end is a hand-rolled `RpcPeerContract` that
calls the `Parlance` service with a custom `BadFrame` whose `toJson` sends any
field type. To run for another hypothesis: change the `cases` map — each entry
is (method, params, field the refusal must name). The caller MUST be pinned to
`RpcDataTransferMode.codec` (see L-1): over a zero-copy-capable pair an
`auto`-mode caller sends objects and the host never runs its request codec.

## Measures

The gRPC status code and message the HOST renders onto the wire for a
badly-typed guest frame, read on the guest side as the received
`RpcStatusException`, plus session/connection liveness after each frame.

## Control

A well-formed `describe` and a well-formed `call` frame are answered (healthy
session), and a semantically bad op through `apply` is refused per-op with a
named error — so the bench can tell a clean refusal from the redacted
`INTERNAL` escape. At validation, with the fix switched off, all ten
badly-typed cases gave status 13 `Internal server error` where the witness
expects 3; with the fix on, all ten give status 3 `invalidArgument` naming the
field:

```
Before (fix off): 10/10 -> 13 internal: Internal server error
After  (fix on):  10/10 ->  3 invalidArgument: "<field>" is not of the expected type: <value>
```
