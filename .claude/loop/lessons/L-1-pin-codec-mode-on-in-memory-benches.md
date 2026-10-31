---
round: 2 — where it was paid for
class: bench
cost: 1 full Before measurement discarded and re-taken — the round's first battery measured the wrong mechanism end to end
paths: [packages/parlance/test/remote/**, packages/parlance/benchmark/**]
commit: 9e3639a3cb55ab22aa9335f91966b18a65e61f3d
status: active
---

# L-1 — pin the hostile caller to codec mode, or the bench measures the wrong path

Over a zero-copy-capable in-memory pair (rpc_dart's `RpcChannelTransport.memoryPair`), a caller whose `RpcDataTransferMode` is `auto` sends OBJECTS, not bytes: the host answers at `directPayload as TRequest` and never runs its request codec. Round 2's first hostile-guest battery therefore "confirmed" the hypothesis against the direct-cast path while the decode path it targeted went unexercised; host-side logs (`payload=0`, `type 'BadFrame' is not a subtype of type 'WireCallRequest'`) exposed it. Any bench that must exercise serialization, codecs or decode has to set `callerDataTransferMode: RpcDataTransferMode.codec` on the sending contract explicitly.
