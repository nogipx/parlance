# Changelog

## Unreleased

- Add atomic server/client/bidirectional stream words with typed input streams, native RPC streaming, half-close, cancellation and propagated flow control.

- Fix stream cancellation reentrancy, paused completion resource release, query effect checks, and availability/feature negotiation after reconnection.

- Release stream factories and callback captures after termination, including retained completed streams; add forced-GC and resource-table regression checks.

- Add `@ServerStreamWord`: typed owner factories and lazy clients, local and remote subscriptions, terminal errors, cancellation and configurable resource bounds.

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
