# Explaining Parlance interactions

Diagnostics use the existing `Cause`: `parent` identifies the preceding
message, `conversation` groups the interaction, and `origin` identifies its
verified beginning. Scheduling, cancellation and retry rules stay with their
existing contracts.

## Contract

- Explanations follow calls, facts, committed changes and stream operations,
  including running operations. Missing history, unresolved parents, cycles and
  depth limits are explicit gaps.
- RPC resolves parents against operations served by that session and readable
  retained facts or changes. A peer cannot supply its own trusted origin.
- A caller's timeout/cancellation and the handler's eventual completion are
  separate outcomes. An unfinished file is not proof of a running handler.
- Journal identity includes the epoch. Ambiguous message IDs are reported.
- Admission, guards, deduplication, limits, stream lifecycle and catalog changes
  are metadata events. Stream elements are never recorded by diagnostics.
- Conversation writes are recorded by default; selected independent state writes
  can be captured by a host-side filter. Coverage and omitted values are explicit.

## Resource ownership

Retained ticks, facts and call records own payload history. Explanation walks
create temporary views, not another payload cache. Additional retained events
contain bounded metadata only, limited by both item count and bytes. Light hosts
retain none. Session parent references contain IDs only and are bounded.
Disposal clears retained data and diagnostic subscriptions. Paused journal
listeners have bounded queues. Metadata-only serialization does not encode or decode native values.

MCP and the viewer consume the same structured explanation and journal data.
Participant inspection enforces its access policy. `parlance_links` is outside
this change.

## Tool API

Import `package:parlance/tools.dart` in inspectors, recorders and MCP adapters.
Use `participant.raw.explain(address, key: key, historyCount: 20)` for a state.
`Explanation.trail` contains heterogeneous `JournalEntry` values, nearest first;
`gap` explains a missing parent or the ten-message walk limit. `forgotten`
distinguishes an evicted last change from a state which was never written.
History is opt-in, bounded to 100 changes, and may be incomplete.

`participant.raw.inspectCall(id)` inspects calls made or served by that participant.
It accepts its own caller-supplied ID or the canonical operation ID and returns
the same bounded, redacted causal trail and explicit gaps as a state explanation. The host's
`registry.pending`, `running`, `diagnostics`, `message(id)` and `inspectCall(id)`
are trusted tooling views. Participant explanations and call inspection redact
payloads against the current access policy, including the inspected message and
late results. RPC requires `causalDiagnostics` and always uses mixed journal
trails with explicit payload visibility; call-only responses are unsupported.
An unresolved RPC parent is preserved as `Cause.unresolvedParent`, never
as a verified `parent` or a peer-supplied origin.

`CallRecord.replyResult` and `repliedAt` preserve the earlier timeout/cancellation
on a late completion. The original result and completion time remain in `result`
and `finished`. This records observations; it does not roll back work.

A host can hold `registry.captureStateWrites([exactAddress])` until its returned
handle is disposed. The capture selection holds immutable names, not callbacks.
The default journal records writes in conversations only.

Journal readers scope IDs by `epoch`; `of`, `pathTo`, `conversation` and `tree`
reject an unspecified epoch when it is ambiguous. `parseJournal(onIssue:)` and
`JournalReader(onIssue:)` report malformed lines, sequence gaps and unreadable
files without retaining their contents. Multi-file readers and the viewer preserve
sequence checks across file boundaries; `JournalParser` does the same for custom
chunk readers, retaining positions for at most 32 epochs. Recorder `capture.started/stopped`
metadata declares coverage and omitted payloads. Independent-write selection is
host-owned and is not enumerated by the recorder; queries and stream elements
are explicitly outside its coverage. `payloads: false` is explicit
and must not be rendered as actual null values.

## Memory limits and verification

- Payloads stay in the existing retained ticks/facts/calls; walks only borrow them.
- Additional metadata is bounded by `retainTicks` and `min(retainBytes, 256 KiB)`.
- Served-parent capabilities are IDs only, bounded by `retainTicks` and 64 KiB.
- A light host retains no added diagnostic history; active/pending operations exist only while work is in flight.
- Paused listeners and synchronous reentrant emissions are limited to 64 entries and 4 MiB; overflow terminates
  the paused listener and releases its backlog. A recorder reports this through onError. Reentrant overflow emits `capture.gap` with its dropped-entry count.
- Recorder flush timers are one-shot, cancelled on close; host disposal clears
  retained observations, calls and paused journal queues, even if application code
  still holds the host or subscription. Discarded unread entries produce a
  terminal recording gap when that listener resumes.

Run affected diagnostic tests first. Cross-topology scenarios are in
`test/registry/diagnostics_test.dart`; forced-GC verification is
`fvm dart --enable-vm-service=0 run tool/diagnostics_retention_probe.dart` from the
parlance package. Keep control objects so collection failures cannot be confused
with a probe that did not actually collect garbage.
