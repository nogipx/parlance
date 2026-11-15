# Changelog

## Unreleased

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
