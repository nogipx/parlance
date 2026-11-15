# Changelog

## 0.4.0

- Breaking: use wire protocol 2 with all current features required; remove old-host downgrades and per-feed feature negotiation.
- Breaking: remove word aliases throughout Host, registry, mirrors, discovery and MCP. Calls no longer drop parameters removed from the current schema.

- Breaking (diagnostics): use only mixed journal trails in `why`; preserve omitted-payload metadata and reject hosts without the current diagnostic contract.
- Enforce current access when inspecting late results, bound journal queue error text, and preserve stream event order during reentrant listeners.
- Refresh the packaged skill and references for explicit targets, protocol 2, current testing APIs and structured diagnostics.

## 0.3.0

- Breaking (tools): `Explanation.trail` now contains mixed `JournalEntry` values. Add bounded causal lookup and call inspection across RPC, pending/admission diagnostics, explicit gaps and selected independent-write capture.
- Preserve caller timeout/cancellation separately from late completion; redact inaccessible ancestor values and report ambiguous reused IDs.
- Bound diagnostic metadata and journal queues; release retained history and paused backlogs on host disposal. Verify lifecycle cleanup with forced GC.

- Breaking: discover targets by vocabulary or portable word name and group their publications in PublishedVocabulary entries. Keep contract checks in typed clients. Generated word packages now expose <Class>Vocabulary.name/words/definition instead of <class>Words; regenerate them.

- Require rpc_dart 7.2.0.

- Breaking: standardize addressing terminology on target across clients, WordAddress, discovery (WordTarget/PublishedWord), runtime helpers, MCP metadata and the targets wire feature. Regenerate word packages; no aliases for former names remain.

- Add Host.setAccess/clearAccess with immutable per-publication overrides, pre-publication configuration and restoration of declared ACLs.
- Propagate live ACL changes through statuses, discovery, aliases, mirrors and subscriptions; revoke active streams and protect retry identity and queued payloads.
- Make Access.warn emit structured developer diagnostics for real interactions through accessWarnings and logs. Advertise accessPolicy on the wire.

- Breaking: scope vocabularies, runtime word addresses and clients to an exact target principal. Client factories require named `participant` (or `owner`) and `target`.
- Add `WordAddress`, `Principal.whole`, target discovery and observable publication/access/schema status. Require the `targets` wire feature.
- Isolate caller-supplied call IDs by caller instance and fact IDs by full publication address; preserve exact receiver addresses through RPC, subscriptions, streams, aliases, diagnostics and journal causes.

- Breaking: remove dynamic choices, `Choice`, `Choices`, `ChoiceType`,
  `@ChoiceOf`, owner/participant registration APIs and `standInChoices`.
  Expose domain catalogs through states or queries and validate IDs in owners;
  keyed states remain, with explicit removal by their owner.
- Remove the `kinds` wire feature and `kind`/`unkind` operations.
- Remove `ITypeContext` and `Shape.checkedAlone`: structural checks now use
  `ValueType.check(value, [path])` and `Shape.check(value, {was})`.

## 0.2.0

- Require rpc_dart 7.1.0 and reuse its integration primitives for stream lifetimes, bounded delivery and buffer accounting while preserving the word API.

- Add atomic server/client/bidirectional stream words with typed input streams, native RPC streaming, half-close, cancellation and propagated flow control.

- Fix stream cancellation reentrancy, paused completion resource release, query effect checks, and availability/feature negotiation after reconnection.

- Harden stream framing, preserve native RPC failure codes, and release pending-opening quotas on RPC cancellation or deadline.

- Add read-only active stream snapshots, bounded lifecycle events, input/output counters, usage tracking and causal spans for host tools.

- Release stream factories and callback captures after termination, including retained completed streams, snapshots and RPC contexts; add forced-GC and resource-table regression checks.

## 0.1.3

- Use the published RPC generator 0.7.1 and regenerate package vocabularies with versioned provenance.

## 0.1.2

- Name the skill with the package prefix required by the installer.

## 0.1.1

- Fix the packaged skill metadata so skill installers can read it.

## 0.1.0

- First published release.
- The public surface of `schema.dart` and `app.dart` is intended to freeze at
  1.0.0; until then 0.x releases may still take things away or change them.
