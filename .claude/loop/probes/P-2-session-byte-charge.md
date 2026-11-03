---
file: packages/parlance/test/remote/session_byte_charge_test.dart
round: 3 — session byte charge gap
commit: 623feb624ff381b718779db8510fe95b24b1d9bd
paths: [packages/parlance/lib/src/remote/session.dart]
status: valid
promoted: packages/parlance/test/remote/session_byte_charge_test.dart
---

# P-2 — session byte charge

A real `RemoteSession` on one end of an `RpcChannelTransport.memoryPair`,
served with default (round 3: tight custom) `SessionLimits`, the guest caller
pinned to `RpcDataTransferMode.codec` (L-1). To run for another hypothesis:
change the ops in `apply` — each entry is one guest-fed retention shape
(define/kind/emit/set), and the per-op results carry the refusal.

## Measures

Host-side retained bytes attributable to the served guest against the only
per-session byte bound (`stateBytes`), and the count of per-session byte
refusals. Descriptors are weighed off the registry's own catalog
(`jsonWeight(registry.stateDescriptor(name).toJson())`); kinds and payloads
are weighed from the identical wire content with the registry's own
`jsonWeight`, the host retaining those strings verbatim.

## Control

A plain `set` of ~2 MiB to the guest's own state — the one charged structure
— is refused `resourceExhausted` by `stateBytes`, so the bench sees a refusal
where a byte charge exists, while the three uncharged shapes pass. At
validation (before the fix), with the session served under the DEFAULT limits:

```
held=19191548 vs stateBytes=1048576; errors=[resourceExhausted: the session holds at most 1048576 bytes of values: g.s0 would make it 2097168]
```

255 fat descriptors + 1000 fat entities + 100 fat payloads, all retained with
zero refusals (19.2 MiB, 18.3x the default bound); only the control set was
refused.
