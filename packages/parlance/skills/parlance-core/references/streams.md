# Stream words: server, client and bidirectional

The developer-facing `schema.dart` exposes the three annotations, typed words,
generated operations and `StreamFailure`/`StreamFailureCode`. Queue configuration
belongs to `app.dart`: `StreamLimits` only has its constructor, four bounds and
`unbounded`. Limit negotiation, JSON conversion and policy merging are internal.
`tools.dart` permits streaming through a raw participant; it does not export
registry mutation extensions or source/lifetime bridges. Even an inspector that
has `Host.registry` must use a participant to define or open a stream.

Three atomic word kinds describe streaming operations:

| Kind | Annotation | Owner signature | Generated client |
| --- | --- | --- | --- |
| `serverStream` | `@ServerStreamWord` | `Stream<O> read({params})` | `Stream<O> read({params, cancel})` |
| `clientStream` | `@ClientStreamWord` | `Future<R> save(Stream<I> input, {params})` | `Future<R> save(Stream<I> input, {params, cancel})` |
| `bidiStream` | `@BidiStreamWord` | `Stream<O> process(Stream<I> input, {params})` | `Stream<O> process(Stream<I> input, {params, cancel})` |

There is no mode flag. Each kind has its own annotation, typed word interface,
generated enum and operation. Input is exactly one required positional, typed
`Stream<I>`; ordinary parameters stay named. Client streams return `Future<R>`; `Future<void>` acknowledges completion without
an application result.
Changing kind at the same name is a word compatibility break. Parameters and
input elements are checked contravariantly; results/output elements covariantly.
Versioning creates a new word beside the old one, as for all other word kinds.

A server stream word names a parameterized sequence of typed data. Its owner returns
`Stream<T>` and chooses whether listeners share a source or get separate work.
Server and bidi clients return a lazy single-subscription stream: each method call creates
a new stream; only listening validates access and parameters and invokes the
owner. Opening again is new work, potentially with side effects and cost.
A client-stream call starts immediately and resolves its Future with the final
result. Input completion is a half-close: a bidi owner may continue sending.
An early result or output completion cancels any remaining input subscription.
Errors in either direction terminate the operation. Token cancellation ends
both directions, including while a client stream waits for its final result.
Arbitrary work started by an owner still requires cooperative cancellation.

Server streams use `readers` (participant readers, else anyone). Client and bidi
streams use `callers` (participant callers, else denied), because they accept
input that may cause effects. Admission precedes invocation of the owner.
Queries may initiate none of the three kinds.

There is no replay, snapshot, deduplication, history, retry or automatic resume.
An owner may provide initial values, history or a cursor in its own contract.
Elements are not facts or ticks and have no ordering relative to state/facts.
Parameters and elements use the same shapes as other words, including locally
kept Dart values. Self-serializing classes keep their existing JsonShape snapshot
semantics even locally. Connections serialize all elements. Binary transport is
not part of this feature.

`@ServerStreamWord(name, version:, readers:, whyNot:, meta:)` marks a method returning
`Stream<T>` with named parameters. Generated owner methods return `Stream<T>`;
generated client methods take the same parameters and optional `cancel:`.
Readers default to the participant's readers, else everyone. Access and
parameters are checked before invoking the owner. `whyNot` prevents new
subscriptions, without ending existing ones. Stream handlers are not queries:
their work is not subject to the query's no-effects rule. `by` identifies the
subscriber during the subscription factory and its asynchronous work; it does
not change the identity of an independently created shared source.
Since opening can start work and effects, a query handler may not subscribe to
a stream. This is checked before invoking an owner, both locally and remotely.

The first error is terminal, including malformed data, missing words, refusal,
overflow, owner withdrawal and connection loss. Failures have stable codes;
recoverable conditions may be typed data. Source completion closes normally.
`cancel()` cancels that source subscription and releases its resources; a
cancel token ends it with a cancelled failure. Other listeners remain intact.
Participant disposal ends incoming and outgoing subscriptions. Cancellation
does not forcibly interrupt arbitrary work or shut down a shared source.

`subscription.cancel()` detaches the consumer without emitting an error or a
done event to that subscription. Its future does not wait for arbitrary owner
work or a remote acknowledgement. A `cancel:` token instead delivers a terminal
`StreamFailure` with code `cancelled`. The cancellation reaches the source
subscription; owner code doing work outside that subscription must cooperate
with `expired` or its own source cleanup. `expired` is signalled on termination.

Closing releases pending elements, token handlers, source subscriptions,
factories and callback captures, even when client code retains the completed
stream or subscription. An unopened lazy stream intentionally keeps its factory
and parameters until it is listened to or dropped.
Cancellation during a factory prevents listening to the stream it returns;
cancellation during element validation/weighing cannot enqueue data afterwards.
A finished source with no queued data releases its slot even when its consumer
is paused; the consumer still receives `done` only after resuming.

Parlance bounds its own pending elements by count and approximate JSON bytes,
and bounds each element and active subscriptions per participant. Defaults:
16 subscriptions, 64 pending elements, 1 MiB pending bytes, 256 KiB per element.
Remote participants bound consumed and provided subscriptions separately, so
subscribing to their own word is not counted twice against the same limit.
Host limits apply locally too; sessions can impose stricter limits. Limits
are configurable and may be unbounded for trusted code. No lifetime or idle
timeout is imposed. Pausing forwards demand through single-subscription sources and RPC bridges.
RPC uses its existing flow-control credit; Parlance adds no pause wire message.
An owner must choose a source that respects pause or bound its own buffering.
Broadcast sources are kept running and use the bounded Parlance queue; one slow
listener never pauses the shared producer. Overflow ends that subscription
explicitly. No element is silently dropped during a healthy subscription. These bounds
cover Parlance queues, not buffers inside arbitrary owner code or transport.

Protocol feature `streams` adds independent server streams in both directions
over the existing peer connection, outside the state/fact feed. Cancellation
propagates through every hop. Losing either connection is terminal, including
when an owner is in another remote participant. Existing streams never rejoin.
New subscriptions may be opened after reconnection. Older peers do not receive
stream descriptors, definitions or built-against entries. Stream use without
feature support fails explicitly. The protocol major remains 1.
On rejoining, stream availability is published again even if `whyNot` did not
change. A host without `streams` receives no stream availability or withdrawal
operations; the participant keeps its definitions for a later supporting host.

Diagnostics log opening and closing, subscription identity, word, subscriber,
element/byte counts and terminal reason, without retaining payload history.
The `inputStreams` protocol feature adds native client-stream (`uploadData`)
and bidi (`exchangeData`) RPC operations on both peer contracts. Their first
frame is the opening header; subsequent frames are input values or terminal
failures. An older peer sees no input-stream definitions or built schemas.
Inputs and outputs use the same validation, cancellation and queue limits.
Schema compatibility distinguishes all three atomic kinds.
MCP stream consumption is a separate interface, not introduced here.

The standalone retention check is
`fvm dart --enable-vm-service=0 run tool/stream_retention_probe.dart` from
`packages/parlance`. It requests full GC through the local VM service and checks
weak references with both live and unreachable controls. It retains completed
streams/subscriptions on purpose, covers all four local/RPC placements and
termination paths, repeats 200 subscriptions, and inspects empty registry,
remote-subscription and long-lived cancellation-token tables. This tests
Parlance's retention, not buffers or unfinished work deliberately kept by an owner.
